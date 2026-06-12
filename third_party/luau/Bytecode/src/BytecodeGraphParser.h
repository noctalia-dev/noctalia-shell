// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/BytecodeGraph.h"
#include "Luau/BytecodeUtils.h"

#include <unordered_set>
#include <algorithm>

LUAU_FASTFLAG(DebugLuauUserDefinedClasses)

namespace Luau
{
namespace Bytecode
{

template<typename VmConst>
struct BytecodeGraphParser
{
    struct LoopInfo
    {
        BcOp entry;
        BcOp exit;
    };

    struct BlockProducers
    {
        std::unordered_map<Reg, BcOp> own;
        std::unordered_map<Reg, BcOp> cached;
        BcOp multiReturn;
        Reg multiReturnStart;
        int invalidAfter = 255;
    };

    using Producers = std::vector<BlockProducers>;

    BcFunction<VmConst>& func;
    std::unordered_map<uint32_t, BcOp> blockByPC;
    Producers producers;
    BcOp currentBlock;

    BytecodeGraphParser(BcFunction<VmConst>& func)
        : func(func)
    {
    }

    void addSuccessor(BcOp fromOp, BcOp toOp, BcBlockEdgeKind kind)
    {
        BcBlock& from = func.blockOp(fromOp);
        BcBlock& to = func.blockOp(toOp);
        from.successors.push_back({kind, toOp});
        to.predecessors.push_back({kind, fromOp});
    }

    BcOp makeBlock(uint32_t pc)
    {
        BcOp newBlockOp = func.addBlock();
        blockByPC[pc] = newBlockOp;
        BcBlock& newBlock = func.blockOp(newBlockOp);
        newBlock.sortkey = pc;
        return newBlockOp;
    }

    bool isJumpTrampoline(uint32_t pc, const Instruction* code, uint32_t codesize)
    {
        return LuauOpcode(LUAU_INSN_OP(code[pc])) == LOP_JUMP && pc + 1 < codesize && LuauOpcode(LUAU_INSN_OP(code[pc + 1])) == LOP_JUMPX &&
               static_cast<uint32_t>(getJumpTarget(code[pc + 2], pc + 2)) == pc + 1;
    }

    size_t rebuildBlocks(const Instruction code[], uint32_t codesize)
    {
        BcOp entryBlock = func.entryBlock = makeBlock(0);
        BcOp exitBlock = func.exitBlock = makeBlock(kBlockNoStartPc);
        uint32_t i = 0;
        BcOp currentBlock = entryBlock;
        size_t instructionCount = 0;
        while (i < codesize)
        {
            Instruction insn = code[i];
            LuauOpcode op = LuauOpcode(LUAU_INSN_OP(insn));
            int target = getJumpTarget(insn, i);
            if (target >= 0 && LuauOpcode(LUAU_INSN_OP(code[target])) == LOP_JUMPX)
                target = getJumpTarget(code[target], target);

            bool needsBlock = target >= 0 && !isFastCall(op) && op != LOP_JUMPX && !isJumpTrampoline(i, code, codesize);
            if (needsBlock)
            {
                if (blockByPC.count(target) == 0)
                {
                    BcOp newBlockOp = makeBlock(target);
                    if (target < static_cast<int>(i)) // We are jumping back.
                    {
                        // The new block was created in the middle of the existing one.
                        // We need to maintain predecessor/successor relations.
                        uint32_t blockStartPc = target - 1;
                        while (blockByPC.count(blockStartPc) == 0 && blockStartPc-- != 0)
                            ;
                        LUAU_ASSERT(blockByPC.count(blockStartPc) > 0);
                        BcOp prevBlockOp = blockByPC[blockStartPc];
                        BcBlock& prevBlock = func.blockOp(prevBlockOp);
                        BcBlock& newBlock = func.blockOp(newBlockOp);
                        // Steal successors of the previous block.
                        newBlock.successors = prevBlock.successors;
                        // Now it should only fallsthrough to the new block.
                        prevBlock.successors.clear();
                        addSuccessor(prevBlockOp, newBlockOp, BcBlockEdgeKind::Fallthrough);
                        // Update all successors to have the new block as a predecessor instead of the old one.
                        for (auto& edge : newBlock.successors)
                            for (auto& backEdge : func.blockOp(edge.target).predecessors)
                                if (backEdge.target == prevBlockOp)
                                    backEdge.target = newBlockOp;
                    }
                }
                addSuccessor(currentBlock, blockByPC[target], isLoopJump(op) ? BcBlockEdgeKind::Loop : BcBlockEdgeKind::Branch);
            }
            if (op == LOP_RETURN)
                addSuccessor(currentBlock, exitBlock, BcBlockEdgeKind::Fallthrough);
            i += getOpLength(op);
            if ((needsBlock || (op == LOP_RETURN && i < codesize)) && blockByPC.count(i) == 0)
                makeBlock(i);

            if (blockByPC.count(i) != 0)
            {
                if (isFallthrough(op))
                    addSuccessor(currentBlock, blockByPC[i], BcBlockEdgeKind::Fallthrough);
                currentBlock = blockByPC[i];
            }
            instructionCount++;
        }
        return instructionCount;
    }

    std::optional<BcOp> findProducer(BcOp block, Reg reg, std::unordered_set<BcOp, BcOpHash>& visited)
    {
        visited.insert(block);
        LUAU_ASSERT(block.index < producers.size());
        BlockProducers& blockProducers = producers.at(block.index);
        if (static_cast<int>(reg) > blockProducers.invalidAfter)
            return {};

        if (auto local = blockProducers.own.find(reg); local != blockProducers.own.end())
        {
            return {local->second};
        }

        if (auto cached = blockProducers.cached.find(reg); cached != blockProducers.cached.end())
        {
            return {cached->second};
        }

        if (blockProducers.multiReturn.kind != BcOpKind::None && reg >= blockProducers.multiReturnStart)
            return func.addProj(blockProducers.multiReturn, reg - blockProducers.multiReturnStart);

        std::unordered_set<BcOp, BcOpHash> results;
        BcBlock& bl = func.blockOp(block);
        for (auto [ctrl, pred] : bl.predecessors)
        {
            if (ctrl == BcBlockEdgeKind::Loop || visited.count(pred) > 0)
                continue;
            LUAU_ASSERT(block != pred);
            if (std::optional<BcOp> op = findProducer(pred, reg, visited))
            {
                if (op->kind == BcOpKind::Phi)
                    for (BcOp& proj : func.phiOp(*op).ops)
                        results.insert(proj);
                else
                    results.insert(*op);
            }
        }
        if (results.size() == 0)
            return {};
        BcOp res;
        if (results.size() == 1)
            res = *results.begin();
        else
        {
            res = func.addPhi();
            BcPhi& phi = func.phiOp(res);
            for (auto op : results)
                phi.ops.push_back(op);
        }
        blockProducers.cached[reg] = res;
        return res;
    }

    std::optional<BcOp> findProducer(BcOp block, Reg reg)
    {
        std::unordered_set<BcOp, BcOpHash> visited;
        return findProducer(block, reg, visited);
    }

    bool hasProducerBefore(BcOp rangeStart, BcOp rangeEnd, BcOp startOp, Reg reg, bool checkCached, std::unordered_set<BcOp, BcOpHash>& visited)
    {
        LUAU_ASSERT(startOp.kind == BcOpKind::Inst);
        visited.insert(rangeEnd);
        LUAU_ASSERT(rangeEnd.index < producers.size());
        BlockProducers& blockProducers = producers.at(rangeEnd.index);
        if (static_cast<int>(reg) > blockProducers.invalidAfter)
            return false;
        BcBlock& bl = func.blockOp(rangeEnd);
        if (blockProducers.multiReturn.kind != BcOpKind::None && reg >= blockProducers.multiReturnStart)
            return true;
        if (checkCached)
        {
            if (blockProducers.own.count(reg) > 0)
                return true;
        }
        else
            for (auto op : bl.ops)
            {
                // We have reached the end of range.
                if (op == startOp)
                    break;
                auto opReg = func.regs.find(op);
                if (opReg != func.regs.end() && opReg->second == reg)
                    return true;
            }
        if (rangeEnd == rangeStart)
            return false;
        for (auto [ctrl, pred] : bl.predecessors)
        {
            if (ctrl == BcBlockEdgeKind::Loop || visited.count(pred) > 0)
                continue;
            if (hasProducerBefore(rangeStart, pred, startOp, reg, true, visited))
                return true;
        }
        return false;
    }

    bool hasProducerBefore(BcOp rangeStart, BcOp rangeEnd, BcOp startOp, Reg reg)
    {
        std::unordered_set<BcOp, BcOpHash> visited;
        return hasProducerBefore(rangeStart, rangeEnd, startOp, reg, false, visited);
    }

    std::optional<BcOp> findForwardProducerInRange(BcOp rangeStart, BcOp rangeEnd, BcOp startOp, Reg reg, std::unordered_set<BcOp, BcOpHash>& visited)
    {
        LUAU_ASSERT(startOp.kind == BcOpKind::Inst);
        visited.insert(rangeEnd);
        LUAU_ASSERT(rangeEnd.index < producers.size());
        BlockProducers& blockProducers = producers.at(rangeEnd.index);
        if (static_cast<int>(reg) > blockProducers.invalidAfter)
            return {};
        BcBlock& bl = func.blockOp(rangeEnd);

        if (auto local = blockProducers.own.find(reg); local != blockProducers.own.end())
            return {local->second};

        if (rangeStart == rangeEnd)
            return {};

        if (blockProducers.multiReturn.kind != BcOpKind::None && reg >= blockProducers.multiReturnStart)
            return blockProducers.multiReturn;

        std::unordered_set<BcOp, BcOpHash> results;
        for (auto [ctrl, pred] : bl.predecessors)
        {
            if (ctrl == BcBlockEdgeKind::Loop || visited.count(pred) > 0)
                continue;
            LUAU_ASSERT(rangeEnd != pred);
            if (std::optional<BcOp> op = findForwardProducerInRange(rangeStart, pred, startOp, reg, visited))
            {
                if (op->kind == BcOpKind::Phi)
                    for (BcOp& proj : func.phiOp(*op).ops)
                        results.insert(proj);
                else
                    results.insert(*op);
            }
        }
        if (results.size() == 0)
            return {};
        BcOp res;
        if (results.size() == 1)
            res = *results.begin();
        else
        {
            res = func.addPhi();
            BcPhi& phi = func.phiOp(res);
            for (auto op : results)
                phi.ops.push_back(op);
        }

        return res;
    }

    std::optional<BcOp> findForwardProducerInRange(BcOp rangeStart, BcOp rangeEnd, BcOp startOp, Reg reg)
    {
        std::unordered_set<BcOp, BcOpHash> visited;
        return findForwardProducerInRange(rangeStart, rangeEnd, startOp, reg, visited);
    }

    std::vector<BcOp> findProducersUpToTop(BcOp block, Reg reg)
    {
        // We assume it called only for search of var return calls.
        LUAU_ASSERT(block.index < producers.size());
        BlockProducers& blockProducers = producers.at(block.index);
        // So we need to find all producers from reg to blockProducers.multiReturnStart.
        LUAU_ASSERT(blockProducers.multiReturn.kind == BcOpKind::Inst);
        std::vector<BcOp> res;
        res.reserve(blockProducers.multiReturnStart - reg + 1);
        for (; reg < blockProducers.multiReturnStart; reg++)
        {
            auto staticRegOp = findProducer(block, reg);
            LUAU_ASSERT(staticRegOp);
            res.push_back(*staticRegOp);
        }
        res.push_back(blockProducers.multiReturn);
        // multireturn is consumed, clean it up
        blockProducers.multiReturn = BcOp{};
        blockProducers.multiReturnStart = 0xFF;
        return res;
    }

    bool isUnreachable(BcOp blockOp)
    {
        if (blockOp == func.entryBlock)
            return false;
        BcBlock& block = func.blockOp(blockOp);
        for (auto [ctrl, pred] : block.predecessors)
        {
            if (ctrl == BcBlockEdgeKind::Loop)
                continue;
            if (!isUnreachable(pred))
                return false;
        }
        return true;
    }

    void addProducer(Reg reg, BcOp op)
    {
        BlockProducers& blockProducers = producers[currentBlock.index];
        blockProducers.own[reg] = op;
        func.regs[op] = reg;
        blockProducers.invalidAfter = std::max(static_cast<int>(reg), blockProducers.invalidAfter);
    }

    void applyCall(BlockProducers& producers, BcOp callOp, Reg targetReg, int nresults)
    {
        for (auto it = producers.own.begin(); it != producers.own.end();)
        {
            if (it->first >= targetReg)
            {
                it = producers.own.erase(it);
            }
            else
            {
                ++it;
            }
        }
        for (auto it = producers.cached.begin(); it != producers.cached.end();)
        {
            if (it->first >= targetReg)
            {
                it = producers.cached.erase(it);
            }
            else
            {
                ++it;
            }
        }
        if (nresults < 0)
        {
            producers.multiReturn = callOp;
            producers.multiReturnStart = targetReg;
            producers.invalidAfter = 255;
        }
        else
        {
            producers.invalidAfter = static_cast<int>(targetReg) - 1 + nresults;
        }
    }

    void addImmInput(BcInst& inst, bool value)
    {
        BcOp op{BcOpKind::Imm, 0};
        size_t i = 0;
        for (; i < func.immediates.size(); i++)
        {
            BcImm& imm = func.immediates[i];
            if (imm.kind == BcImmKind::Boolean && imm.valueBoolean == value)
            {
                op.index = i;
                break;
            }
        }
        if (i == func.immediates.size())
        {
            func.immediates.push_back({BcImmKind::Boolean, {value}});
            op.index = i;
        }
        inst.ops.push_back(op);
    }

    void addImmInput(BcInst& inst, int32_t value)
    {
        BcOp op{BcOpKind::Imm, 0};
        size_t i = 0;
        for (; i < func.immediates.size(); i++)
        {
            BcImm& imm = func.immediates[i];
            if (imm.kind == BcImmKind::Int && imm.valueInt == value)
            {
                op.index = i;
                break;
            }
        }
        if (i == func.immediates.size())
        {
            func.immediates.push_back({BcImmKind::Int});
            func.immediates.back().valueInt = value;
            op.index = i;
        }
        inst.ops.push_back(op);
    }

    void addImmInput(BcInst& inst, uint32_t value)
    {
        BcOp op{BcOpKind::Imm, 0};
        func.immediates.push_back({BcImmKind::Import});
        func.immediates.back().valueImport = value;
        op.index = func.immediates.size() - 1;
        inst.ops.push_back(op);
    }

    void addVmConstInput(BcInst& inst, uint32_t idx)
    {
        LUAU_ASSERT(idx < func.constants.size());
        inst.ops.push_back(BcOp{BcOpKind::VmConst, idx});
    }

    void addUpvalInput(BcInst& inst, uint32_t idx)
    {
        LUAU_ASSERT(idx < func.nups);
        inst.ops.push_back(BcOp{BcOpKind::VmUpvalue, idx});
    }

    void addProtoInput(BcInst& inst, uint32_t idx)
    {
        inst.ops.push_back(BcOp{BcOpKind::VmProto, idx});
    }

    void addVmRegInput(BcInst& inst, Reg reg)
    {
        std::optional<BcOp> source = findProducer(currentBlock, reg);
        if (!source && isUnreachable(currentBlock))
        {
            inst.ops.push_back(BcOp{BcOpKind::VmReg, reg});
            return;
        }
        LUAU_ASSERT(source);
        inst.ops.push_back(*source);
    }

    void addJumpInput(BcInst& inst, int target)
    {
        LUAU_ASSERT(!isFastCall(inst.op));
        if (target < 0)
        {
            LUAU_ASSERT(inst.op == LOP_LOADB);
            return;
        }
        auto it = blockByPC.find(target);
        LUAU_ASSERT(it != blockByPC.end());
        inst.ops.push_back(it->second);
    }

    BcOp addToPhi(BcOp op, BcOp proj)
    {
        if (op.kind == BcOpKind::Phi)
        {
            BcPhi& phi = func.phiOp(op);
            for (auto p : phi.ops)
                if (p == proj)
                    return op;
            phi.ops.push_back(proj);
            return op;
        }
        else
        {
            BcOp res = func.addPhi();
            BcPhi& phi = func.phiOp(res);
            phi.ops = {op, proj};
            return res;
        }
    }

    static const uint32_t kMaxCFGBlocks = 1000;

    bool rebuildGraph(const Instruction code[], uint32_t codesize, std::vector<uint32_t>& lines, std::vector<uint32_t>& pcs)
    {
        size_t instructionsCount = rebuildBlocks(code, codesize);
        if (blockByPC.size() > kMaxCFGBlocks)
            return false;

        std::vector<LoopInfo> loops;

        producers.resize(func.blocks.size());
        pcs.resize(codesize);

        currentBlock = func.entryBlock;

        for (Reg i = 0; i < func.numparams; i++)
            addProducer(i, {BcOpKind::VmReg, i});

        // Create instructions.
        currentBlock = func.entryBlock;
        func.instructions.reserve(instructionsCount);

        for (uint32_t i = 0; i < codesize;)
        {
            Instruction insn = code[i];
            LuauOpcode op = LuauOpcode(LUAU_INSN_OP(insn));
            int opLength = getOpLength(op);
            uint32_t aux = (opLength > 1 && i + 1 < codesize) ? code[i + 1] : 0;
            BcOp nodeOp = func.addInst();
            func.blockOp(currentBlock).appendInstruction(nodeOp);
            BcInst& node = func.instOp(nodeOp);
            node.block = currentBlock;
            if (i < lines.size())
                node.line = lines[i];
            node.op = op;

            pcs[i] = nodeOp.index;

            auto parseJump = [&](LuauOpcode op, int jumpTarget) -> void
            {
                node.op = op;
                switch (op)
                {
                case LOP_JUMPXEQKNIL:
                    addVmRegInput(node, LUAU_INSN_A(insn));
                    addImmInput(node, static_cast<bool>(aux >> 31));
                    addJumpInput(node, jumpTarget);
                    break;

                case LOP_JUMPXEQKB:
                    addVmRegInput(node, LUAU_INSN_A(insn));
                    addImmInput(node, static_cast<bool>(aux >> 31));
                    addJumpInput(node, jumpTarget);
                    addImmInput(node, static_cast<bool>(aux & 0x1));
                    break;

                case LOP_JUMPXEQKN:
                case LOP_JUMPXEQKS:
                    addVmRegInput(node, LUAU_INSN_A(insn));
                    addImmInput(node, static_cast<bool>(aux >> 31));
                    addJumpInput(node, jumpTarget);
                    addVmConstInput(node, aux & 0xFFFFFF);
                    break;

                case LOP_JUMPIF:
                case LOP_JUMPIFNOT:
                    addVmRegInput(node, LUAU_INSN_A(insn));
                    addJumpInput(node, jumpTarget);
                    break;

                case LOP_JUMPIFEQ:
                case LOP_JUMPIFLE:
                case LOP_JUMPIFLT:
                case LOP_JUMPIFNOTEQ:
                case LOP_JUMPIFNOTLE:
                case LOP_JUMPIFNOTLT:
                    addVmRegInput(node, LUAU_INSN_A(insn));
                    addVmRegInput(node, aux);
                    addJumpInput(node, jumpTarget);
                    break;

                case LOP_FORNPREP:
                    // forg loop protocol: A, A+1, A+2 are used for iteration protocol; A+3, ... are loop variables
                    addVmRegInput(node, LUAU_INSN_A(insn));
                    addVmRegInput(node, LUAU_INSN_A(insn) + 1);
                    addVmRegInput(node, LUAU_INSN_A(insn) + 2);
                    addJumpInput(node, jumpTarget);
                    func.regs[nodeOp] = LUAU_INSN_A(insn);
                    addProducer(LUAU_INSN_A(insn), func.addProj(nodeOp, 0));
                    addProducer(LUAU_INSN_A(insn) + 1, func.addProj(nodeOp, 1));
                    addProducer(LUAU_INSN_A(insn) + 2, func.addProj(nodeOp, 2));
                    break;

                case LOP_FORNLOOP:
                    addVmRegInput(node, LUAU_INSN_A(insn));
                    addVmRegInput(node, LUAU_INSN_A(insn) + 1);
                    addVmRegInput(node, LUAU_INSN_A(insn) + 2);
                    addJumpInput(node, jumpTarget);
                    break;

                default:
                    LUAU_UNREACHABLE();
                }
            };
            switch (op)
            {
            case LOP_NOP:
            case LOP_BREAK:
            case LOP_NATIVECALL:
                break;

            case LOP_LOADNIL:
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_LOADB:
                addImmInput(node, static_cast<bool>(LUAU_INSN_B(insn)));
                addJumpInput(node, getJumpTarget(insn, i));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_LOADN:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_D(insn)));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_LOADK:
                addVmConstInput(node, LUAU_INSN_D(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_MOVE:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_GETGLOBAL:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                addVmConstInput(node, aux);
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_SETGLOBAL:
                addVmRegInput(node, LUAU_INSN_A(insn));
                addImmInput(node, static_cast<uint8_t>(LUAU_INSN_C(insn)));
                addVmConstInput(node, aux);
                break;

            case LOP_GETUPVAL:
                addUpvalInput(node, LUAU_INSN_B(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_SETUPVAL:
                addVmRegInput(node, LUAU_INSN_A(insn));
                addUpvalInput(node, LUAU_INSN_B(insn));
                break;

            case LOP_CLOSEUPVALS:
                node.ops.push_back(BcOp{BcOpKind::VmReg, LUAU_INSN_A(insn)});
                break;

            case LOP_GETIMPORT:
            {
                addVmConstInput(node, LUAU_INSN_D(insn));
                addImmInput(node, aux);
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;
            }

            case LOP_GETTABLE:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmRegInput(node, LUAU_INSN_C(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_SETTABLE:
                addVmRegInput(node, LUAU_INSN_A(insn));
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmRegInput(node, LUAU_INSN_C(insn));
                break;

            case LOP_GETUDATAKS:
            case LOP_GETTABLEKS:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                addVmConstInput(node, aux);
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_SETUDATAKS:
            case LOP_SETTABLEKS:
                addVmRegInput(node, LUAU_INSN_A(insn));
                addVmRegInput(node, LUAU_INSN_B(insn));
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                addVmConstInput(node, aux);
                break;

            case LOP_GETTABLEN:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn) + 1));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_SETTABLEN:
                addVmRegInput(node, LUAU_INSN_A(insn));
                addVmRegInput(node, LUAU_INSN_B(insn));
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn) + 1));
                break;

            case LOP_NEWCLOSURE:
                addProtoInput(node, LUAU_INSN_D(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_NAMECALLUDATA:
            case LOP_NAMECALL:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                addVmConstInput(node, aux);
                func.regs[nodeOp] = LUAU_INSN_A(insn);
                addProducer(LUAU_INSN_A(insn), func.addProj(nodeOp, 0));
                addProducer(LUAU_INSN_A(insn) + 1, func.addProj(nodeOp, 1));
                break;

            case LOP_CALL:
            case LOP_CALLFB:
            {
                int nparams = LUAU_INSN_B(insn) - 1;
                int nresults = LUAU_INSN_C(insn) - 1;
                addImmInput(node, static_cast<int32_t>(nparams));
                addImmInput(node, static_cast<int32_t>(nresults));
                if (op == LOP_CALLFB)
                    addImmInput(node, static_cast<int32_t>(aux));

                // Call target.
                addVmRegInput(node, LUAU_INSN_A(insn));
                // Fixed arguments.
                for (int i = 1; i <= nparams; i++)
                    addVmRegInput(node, LUAU_INSN_A(insn) + i);

                if (nparams < 0)
                {
                    // all arguments prepared before call in the same block
                    for (auto& inp : findProducersUpToTop(currentBlock, LUAU_INSN_A(insn) + 1))
                        node.ops.push_back(inp);
                }

                BlockProducers& blockProducers = producers[currentBlock.index];
                applyCall(blockProducers, nodeOp, LUAU_INSN_A(insn), nresults);

                func.regs[nodeOp] = LUAU_INSN_A(insn);
                for (int i = 0; i < nresults; i++)
                    addProducer(LUAU_INSN_A(insn) + i, func.addProj(nodeOp, i));
                break;
            }

            case LOP_RETURN:
            {
                int nresults = LUAU_INSN_B(insn) - 1;
                addImmInput(node, static_cast<int32_t>(nresults));
                for (int i = 0; i < nresults; i++)
                    addVmRegInput(node, LUAU_INSN_A(insn) + i);
                if (nresults < 0)
                    for (auto& inp : findProducersUpToTop(currentBlock, LUAU_INSN_A(insn)))
                        node.ops.push_back(inp);
                if (nresults == 0)
                    node.ops.push_back(BcOp{BcOpKind::VmReg, LUAU_INSN_A(insn)});
                break;
            }

            case LOP_JUMP:
            {
                if (isJumpTrampoline(i, code, codesize))
                {
                    // it is long jump trampoline
                    int longOffset = LUAU_INSN_E(code[i + 1]);
                    i += getOpLength(LOP_JUMP) + getOpLength(LOP_JUMPX);
                    op = LuauOpcode(LUAU_INSN_OP(code[i]));
                    opLength = getOpLength(op);
                    aux = (opLength > 1 && i + 1 < codesize) ? code[i + 1] : 0;
                    parseJump(op, i + longOffset);
                }
                else
                    addJumpInput(node, getJumpTarget(insn, i));
                break;
            }

            case LOP_JUMPBACK:
                // repeat .. until loops use it for back edge.
                addJumpInput(node, getJumpTarget(insn, i));
                break;

            case LOP_JUMPXEQKNIL:
            case LOP_JUMPXEQKB:
            case LOP_JUMPXEQKN:
            case LOP_JUMPXEQKS:
            case LOP_JUMPIF:
            case LOP_JUMPIFNOT:
            case LOP_JUMPIFEQ:
            case LOP_JUMPIFLE:
            case LOP_JUMPIFLT:
            case LOP_JUMPIFNOTEQ:
            case LOP_JUMPIFNOTLE:
            case LOP_JUMPIFNOTLT:
            case LOP_FORNPREP:
            case LOP_FORNLOOP:
                parseJump(op, getJumpTarget(insn, i));
                break;

            case LOP_ADD:
            case LOP_SUB:
            case LOP_MUL:
            case LOP_DIV:
            case LOP_MOD:
            case LOP_POW:
            case LOP_AND:
            case LOP_OR:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmRegInput(node, LUAU_INSN_C(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_ADDK:
            case LOP_SUBK:
            case LOP_MULK:
            case LOP_DIVK:
            case LOP_MODK:
            case LOP_POWK:
            case LOP_ANDK:
            case LOP_ORK:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmConstInput(node, LUAU_INSN_C(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_CONCAT:
            {
                LUAU_ASSERT(LUAU_INSN_B(insn) <= LUAU_INSN_C(insn));
                for (Reg param = LUAU_INSN_B(insn); param <= LUAU_INSN_C(insn); param++)
                    addVmRegInput(node, param);
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;
            }

            case LOP_NOT:
            case LOP_MINUS:
            case LOP_LENGTH:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_NEWTABLE:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_B(insn)));
                addImmInput(node, static_cast<int32_t>(aux));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_DUPTABLE:
                addProducer(LUAU_INSN_A(insn), nodeOp);
                addVmConstInput(node, LUAU_INSN_D(insn));
                break;

            case LOP_SETLIST:
            {
                int count = LUAU_INSN_C(insn) - 1;
                addImmInput(node, static_cast<int32_t>(aux));
                addImmInput(node, static_cast<int32_t>(count));
                addVmRegInput(node, LUAU_INSN_A(insn));
                for (Reg param = 0; param < count; param++)
                    addVmRegInput(node, LUAU_INSN_B(insn) + param);
                if (count < 0)
                    for (auto inp : findProducersUpToTop(currentBlock, LUAU_INSN_B(insn)))
                        node.ops.push_back(inp);
                break;
            }

            case LOP_FORGPREP:
            case LOP_FORGPREP_NEXT:
            case LOP_FORGPREP_INEXT:
            {
                addVmRegInput(node, LUAU_INSN_A(insn));
                addVmRegInput(node, LUAU_INSN_A(insn) + 1);
                addVmRegInput(node, LUAU_INSN_A(insn) + 2);
                int loopInsnPc = getJumpTarget(insn, i);
                addJumpInput(node, loopInsnPc);
                LUAU_ASSERT(loopInsnPc + 1 < static_cast<int>(codesize) && LuauOpcode(LUAU_INSN_OP(code[loopInsnPc])) == LOP_FORGLOOP);
                int32_t vars = code[loopInsnPc + 1] & 0xFF;
                func.regs[nodeOp] = LUAU_INSN_A(insn);
                for (int i = 0; i <= std::max(vars, 2); i++)
                    addProducer(LUAU_INSN_A(insn) + 2 + i, func.addProj(nodeOp, 2 + i));
                break;
            }

            case LOP_FORGLOOP:
            {
                addVmRegInput(node, LUAU_INSN_A(insn));
                addVmRegInput(node, LUAU_INSN_A(insn) + 1);
                addVmRegInput(node, LUAU_INSN_A(insn) + 2);
                addImmInput(node, static_cast<bool>(aux >> 31));
                int32_t vars = aux & 0xFF;
                addImmInput(node, vars);
                addJumpInput(node, getJumpTarget(insn, i));
                break;
            }

            case LOP_FASTCALL:
                // Note that FASTCALL will read the actual call arguments, such as argument/result registers and counts, from the CALL instruction
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_A(insn)));
                // turn it in BcOp to CALL BcInst&.
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                break;

            case LOP_FASTCALL1:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_A(insn)));
                addVmRegInput(node, LUAU_INSN_B(insn));
                // turn it in BcOp to CALL BcInst&.
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                break;

            case LOP_FASTCALL2:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_A(insn)));
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmRegInput(node, aux & 0xFF);
                // turn it in BcOp to CALL BcInst&.
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                break;

            case LOP_FASTCALL2K:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_A(insn)));
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmConstInput(node, aux);
                // turn it in BcOp to CALL BcInst&.
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                break;

            case LOP_FASTCALL3:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_A(insn)));
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmRegInput(node, aux & 0xFF);
                addVmRegInput(node, (aux >> 8) & 0xFF);
                // turn it in BcOp to CALL BcInst&.
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                break;

            case LOP_GETVARARGS:
            {
                node.ops.push_back(BcOp{BcOpKind::VmReg, LUAU_INSN_A(insn)});
                int count = LUAU_INSN_B(insn) - 1;
                addImmInput(node, static_cast<int32_t>(count));
                func.regs[nodeOp] = LUAU_INSN_A(insn);
                if (count < 0)
                {
                    BlockProducers& blockProducers = producers[currentBlock.index];
                    blockProducers.multiReturn = nodeOp;
                    blockProducers.multiReturnStart = LUAU_INSN_A(insn);
                    blockProducers.invalidAfter = 255;
                }
                else
                    for (int i = 0; i < count; i++)
                        addProducer(LUAU_INSN_A(insn) + i, func.addProj(nodeOp, i));
                break;
            }

            case LOP_DUPCLOSURE:
                addVmConstInput(node, LUAU_INSN_D(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_PREPVARARGS:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_A(insn)));
                break;

            case LOP_LOADKX:
                addVmConstInput(node, aux);
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_JUMPX:
                LUAU_ASSERT(!"Shouldn't parse it directly");
                addJumpInput(node, getJumpTarget(insn, i));
                break;

            case LOP_COVERAGE:
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_E(insn)));
                break;

            case LOP_CAPTURE:
            {
                uint8_t captureType = LUAU_INSN_A(insn);
                addImmInput(node, static_cast<int32_t>(captureType));
                if (captureType == LCT_VAL || captureType == LCT_REF)
                    addVmRegInput(node, LUAU_INSN_B(insn));
                else
                    addUpvalInput(node, LUAU_INSN_B(insn));
                addImmInput(node, static_cast<int32_t>(LUAU_INSN_C(insn)));
                break;
            }

            case LOP_SUBRK:
            case LOP_DIVRK:
                addVmConstInput(node, LUAU_INSN_B(insn));
                addVmRegInput(node, LUAU_INSN_C(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_IDIV:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmRegInput(node, LUAU_INSN_C(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_IDIVK:
                addVmRegInput(node, LUAU_INSN_B(insn));
                addVmConstInput(node, LUAU_INSN_C(insn));
                addProducer(LUAU_INSN_A(insn), nodeOp);
                break;

            case LOP_CMPPROTO:
                addVmRegInput(node, LUAU_INSN_A(insn));
                addImmInput(node, static_cast<int32_t>(aux));
                addJumpInput(node, getJumpTarget(insn, i));
                break;

            case LOP_NEWCLASSMEMBER:
                LUAU_ASSERT(FFlag::DebugLuauUserDefinedClasses);
                addVmRegInput(node, LUAU_INSN_A(insn));
                addVmRegInput(node, LUAU_INSN_C(insn));
                addVmConstInput(node, aux);
                break;


            case LOP__COUNT:
                LUAU_UNREACHABLE();
            }

            if (isLoopJump(op))
            {
                int target = getJumpTarget(insn, i);
                LUAU_ASSERT(target >= 0 && blockByPC.count(target) > 0);
                loops.push_back({blockByPC[target], currentBlock});
            }

            i += opLength;
            if (blockByPC.count(i) > 0)
                currentBlock = blockByPC[i];
        }

        for (auto& loop : loops)
        {
            std::unordered_set<BcOp, BcOpHash> visited;
            std::vector<BcOp> queue;
            queue.push_back(loop.exit);
            while (queue.size() > 0)
            {
                BcOp cur = queue.back();
                queue.pop_back();
                if (visited.count(cur) > 0)
                    continue;
                visited.insert(cur);
                BcBlock& curBlock = func.blockOp(cur);

                for (auto op : curBlock.ops)
                    for (auto& inp : func.instOp(op).ops)
                    {
                        auto regIt = func.regs.find(inp);
                        if (regIt == func.regs.end())
                            continue;
                        // try to find it in the same loop before
                        if (hasProducerBefore(loop.entry, cur, op, regIt->second))
                            continue;
                        if (auto forwardInput = findForwardProducerInRange(cur, loop.exit, op, regIt->second))
                        {
                            inp = addToPhi(inp, *forwardInput);
                            func.regs[inp] = regIt->second;
                        }
                    }

                for (auto& [ctrl, pred] : curBlock.predecessors)
                    if (ctrl != BcBlockEdgeKind::Loop && visited.count(pred) == 0)
                        queue.push_back(pred);
            }
        }
        return true;
    }
};

} // namespace Bytecode
} // namespace Luau