// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/BytecodeGraph.h"
#include "Luau/BytecodeUtils.h"
#include "Luau/BytecodeOps.h"

namespace Luau
{
namespace Bytecode
{

template<typename VmConst>
struct BytecodeGraphSerializer
{
    struct JumpInfo
    {
        LuauOpcode op;
        uint32_t instructionPC;
        BcOp targetBlock;
    };
    using Jumps = std::vector<JumpInfo>;

    BytecodeBuilder& bcb;
    BcFunction<VmConst>& func;
    Jumps jumps;
    bool error = false;

    BytecodeGraphSerializer(BytecodeBuilder& bcb, BcFunction<VmConst>& func)
        : bcb(bcb)
        , func(func)
    {
    }

    std::vector<BcOp> reschedule()
    {
        std::vector<BcOp> sortedBlocks;
        sortedBlocks.reserve(func.blocks.size());
        for (uint32_t i = 0; i < func.blocks.size(); i++)
            if ((func.blocks[i].flags & BcBlockFlag::Dead) == 0)
                sortedBlocks.push_back(BcOp{BcOpKind::Block, i});

        std::sort(
            sortedBlocks.begin(),
            sortedBlocks.end(),
            [&](BcOp opA, BcOp opB)
            {
                const BcBlock& a = func.blockOp(opA);
                const BcBlock& b = func.blockOp(opB);

                if (a.sortkey == b.sortkey)
                    return a.chainkey < b.chainkey;

                return a.sortkey < b.sortkey;
            }
        );

        LUAU_ASSERT(sortedBlocks.back() == func.exitBlock);
        sortedBlocks.pop_back();

        return sortedBlocks;
    }

    uint8_t getRegister(BcOp op)
    {
        switch (op.kind)
        {
        case BcOpKind::Phi:
        {
            BcPhi& phi = func.phiOp(op);
            LUAU_ASSERT(phi.ops.size() > 0);
            LUAU_ASSERT(phi.ops[0] != op);
            Reg res = getRegister(phi.ops[0]);
            for (auto phiOp : phi.ops)
                LUAU_ASSERT(res == getRegister(phiOp));
            return res;
        }
        case BcOpKind::Inst:
        {
            auto it = func.regs.find(op);
            LUAU_ASSERT(it != func.regs.end());
            return it->second;
        }
        case BcOpKind::Proj:
        {
            BcProj& proj = func.projOp(op);
            Reg base = getRegister(proj.op);
            return base + proj.index;
        }
        case BcOpKind::VmReg:
            return op.index;
        default:
            LUAU_UNREACHABLE();
        }
        return 0;
    }

    BcImm& getImm(BcInst& insn, uint8_t index)
    {
        LUAU_ASSERT(index < insn.ops.size());
        BcOp inp = insn.ops[index];
        LUAU_ASSERT(inp.kind == BcOpKind::Imm);
        return func.immOp(inp);
    }

    int32_t getImmInt(BcInst& insn, uint8_t index)
    {
        BcImm& imm = getImm(insn, index);
        LUAU_ASSERT(imm.kind == BcImmKind::Int);
        return imm.valueInt;
    }

    bool getImmBool(BcInst& insn, uint8_t index)
    {
        BcImm& imm = getImm(insn, index);
        LUAU_ASSERT(imm.kind == BcImmKind::Boolean);
        return imm.valueBoolean;
    }

    uint32_t getImmImport(BcInst& insn, uint8_t index)
    {
        BcImm& imm = getImm(insn, index);
        LUAU_ASSERT(imm.kind == BcImmKind::Import);
        return imm.valueImport;
    }

    virtual uint32_t getVmConstInputRaw(BcInst& insn, uint8_t index)
    {
        LUAU_ASSERT(index < insn.ops.size());
        BcOp inp = insn.ops[index];
        LUAU_ASSERT(inp.kind == BcOpKind::VmConst);
        LUAU_ASSERT(inp.index < func.constants.size());
        return inp.index;
    }

    uint8_t getVmConstInputABC(BcInst& insn, uint8_t index)
    {
        uint32_t cid = getVmConstInputRaw(insn, index);

        if (cid > 0xff)
            error = true;

        return uint8_t(cid);
    }

    uint16_t getVmConstInputD(BcInst& insn, uint8_t index)
    {
        uint32_t cid = getVmConstInputRaw(insn, index);

        if (cid > 0xffff)
            error = true;

        return uint16_t(cid);
    }

    uint32_t getVmConstInputAux(BcInst& insn, uint8_t index)
    {
        return getVmConstInputRaw(insn, index);
    }

    uint8_t getUpvalInput(BcInst& insn, uint8_t index)
    {
        LUAU_ASSERT(index < insn.ops.size());
        BcOp inp = insn.ops[index];
        LUAU_ASSERT(inp.kind == BcOpKind::VmUpvalue);
        LUAU_ASSERT(inp.index < func.nups);
        return uint8_t(inp.index);
    }

    uint16_t getProtoInput(BcInst& insn, uint8_t index)
    {
        LUAU_ASSERT(index < insn.ops.size());
        BcOp inp = insn.ops[index];
        LUAU_ASSERT(inp.kind == BcOpKind::VmProto);

        if (inp.index > 0xffff)
            error = true;

        return uint16_t(inp.index);
    }

    uint8_t getRegInput(BcInst& insn, uint8_t index)
    {
        LUAU_ASSERT(index < insn.ops.size());
        return getRegister(insn.ops[index]);
    }

    void recordJump(BcInst& insn, uint8_t index)
    {
        LUAU_ASSERT(index < insn.ops.size());
        BcOp inp = insn.ops[index];
        LUAU_ASSERT(inp.kind == BcOpKind::Block);
        jumps.push_back({insn.op, static_cast<uint32_t>(bcb.getInstructionCount()), inp});
    }

    void patchJump(JumpInfo& jump)
    {
        BcBlock& target = func.blockOp(jump.targetBlock);
        LUAU_ASSERT(target.startpc != kBlockNoStartPc);
        if (isJumpD(jump.op))
        {
            [[maybe_unused]] bool patched = bcb.patchJumpD(jump.instructionPC, target.startpc);
            LUAU_ASSERT(patched);
        }
        else if (isSkipC(jump.op))
        {
            [[maybe_unused]] bool patched = bcb.patchSkipC(jump.instructionPC, target.startpc);
            LUAU_ASSERT(patched);
        }
    }

    void emitInstruction(BcOp insnOp)
    {
        BcInst& insn = func.instOp(insnOp);
        bcb.setDebugLine(insn.line);
        switch (insn.op)
        {
        case LOP_NOP:
        case LOP_BREAK:
        case LOP_NATIVECALL:
            bcb.emitABC(insn.op, 0, 0, 0);
            break;

        case LOP_LOADNIL:
            bcb.emitABC(LOP_LOADNIL, getRegister(insnOp), 0, 0);
            break;

        case LOP_LOADB:
        {
            if (insn.ops.size() > 1)
                recordJump(insn, 1);
            bcb.emitABC(LOP_LOADB, getRegister(insnOp), getImmBool(insn, 0), 0);
            break;
        }

        case LOP_LOADN:
            bcb.emitAD(LOP_LOADN, getRegister(insnOp), getImmInt(insn, 0));
            break;

        case LOP_LOADK:
            bcb.emitAD(LOP_LOADK, getRegister(insnOp), getVmConstInputD(insn, 0));
            break;

        case LOP_MOVE:
            bcb.emitABC(LOP_MOVE, getRegister(insnOp), getRegInput(insn, 0), 0);
            break;

        case LOP_GETGLOBAL:
            bcb.emitABC(LOP_GETGLOBAL, getRegister(insnOp), 0, getImmInt(insn, 0));
            bcb.emitAux(getVmConstInputAux(insn, 1));
            break;

        case LOP_SETGLOBAL:
            bcb.emitABC(LOP_SETGLOBAL, getRegInput(insn, 0), 0, getImmInt(insn, 1));
            bcb.emitAux(getVmConstInputAux(insn, 2));
            break;

        case LOP_GETUPVAL:
            bcb.emitABC(LOP_GETUPVAL, getRegister(insnOp), getUpvalInput(insn, 0), 0);
            break;

        case LOP_SETUPVAL:
            bcb.emitABC(LOP_SETUPVAL, getRegInput(insn, 0), getUpvalInput(insn, 1), 0);
            break;

        case LOP_CLOSEUPVALS:
            LUAU_ASSERT(insn.ops.size() == 1 && insn.ops[0].kind == BcOpKind::VmReg);
            bcb.emitABC(LOP_CLOSEUPVALS, insn.ops[0].index, 0, 0);
            break;

        case LOP_GETIMPORT:
        {
            bcb.emitAD(LOP_GETIMPORT, getRegister(insnOp), getVmConstInputD(insn, 0));
            bcb.emitAux(getImmImport(insn, 1));
            break;
        }

        case LOP_GETTABLE:
            bcb.emitABC(LOP_GETTABLE, getRegister(insnOp), getRegInput(insn, 0), getRegInput(insn, 1));
            break;

        case LOP_SETTABLE:
            bcb.emitABC(LOP_SETTABLE, getRegInput(insn, 0), getRegInput(insn, 1), getRegInput(insn, 2));
            break;

        case LOP_GETUDATAKS:
        case LOP_GETTABLEKS:
            bcb.emitABC(insn.op, getRegister(insnOp), getRegInput(insn, 0), getImmInt(insn, 1));
            bcb.emitAux(getVmConstInputAux(insn, 2));
            break;

        case LOP_SETUDATAKS:
        case LOP_SETTABLEKS:
            bcb.emitABC(insn.op, getRegInput(insn, 0), getRegInput(insn, 1), getImmInt(insn, 2));
            bcb.emitAux(getVmConstInputAux(insn, 3));
            break;

        case LOP_GETTABLEN:
            bcb.emitABC(LOP_GETTABLEN, getRegister(insnOp), getRegInput(insn, 0), getImmInt(insn, 1) - 1);
            break;

        case LOP_SETTABLEN:
            bcb.emitABC(LOP_SETTABLEN, getRegInput(insn, 0), getRegInput(insn, 1), getImmInt(insn, 2) - 1);
            break;

        case LOP_NEWCLOSURE:
            bcb.emitAD(LOP_NEWCLOSURE, getRegister(insnOp), getProtoInput(insn, 0));
            break;

        case LOP_NAMECALLUDATA:
        case LOP_NAMECALL:
            bcb.emitABC(insn.op, getRegister(insnOp), getRegInput(insn, 0), getImmInt(insn, 1));
            bcb.emitAux(getVmConstInputAux(insn, 2));
            break;

        case LOP_CALL:
            bcb.emitABC(LOP_CALL, getRegInput(insn, 2), getImmInt(insn, 0) + 1, getImmInt(insn, 1) + 1);
            break;

        case LOP_CALLFB:
            bcb.emitABC(LOP_CALLFB, getRegInput(insn, 3), getImmInt(insn, 0) + 1, getImmInt(insn, 1) + 1);
            bcb.emitAux(getImmInt(insn, 2));
            break;

        case LOP_RETURN:
        {
            LUAU_ASSERT(insn.ops.size() > 1);
            bcb.emitABC(LOP_RETURN, getRegInput(insn, 1), getImmInt(insn, 0) + 1, 0);
            break;
        }

        case LOP_JUMP:
            recordJump(insn, 0);
            bcb.emitAD(LOP_JUMP, 0, 0);
            break;

        case LOP_JUMPBACK:
            recordJump(insn, 0);
            bcb.emitAD(LOP_JUMPBACK, 0, 0);
            break;

        case LOP_JUMPIFNOT:
        case LOP_JUMPIF:
            recordJump(insn, 1);
            bcb.emitAD(insn.op, getRegInput(insn, 0), 0);
            break;

        case LOP_JUMPIFEQ:
        case LOP_JUMPIFLE:
        case LOP_JUMPIFLT:
        case LOP_JUMPIFNOTEQ:
        case LOP_JUMPIFNOTLE:
        case LOP_JUMPIFNOTLT:
            recordJump(insn, 2);
            bcb.emitAD(insn.op, getRegInput(insn, 0), 0);
            bcb.emitAux(getRegInput(insn, 1));
            break;

        case LOP_ADD:
        case LOP_SUB:
        case LOP_MUL:
        case LOP_DIV:
        case LOP_MOD:
        case LOP_POW:
        case LOP_AND:
        case LOP_OR:
            bcb.emitABC(insn.op, getRegister(insnOp), getRegInput(insn, 0), getRegInput(insn, 1));
            break;

        case LOP_ADDK:
        case LOP_SUBK:
        case LOP_MULK:
        case LOP_DIVK:
        case LOP_MODK:
        case LOP_POWK:
        case LOP_ANDK:
        case LOP_ORK:
            bcb.emitABC(insn.op, getRegister(insnOp), getRegInput(insn, 0), getVmConstInputABC(insn, 1));
            break;

        case LOP_CONCAT:
            LUAU_ASSERT(insn.ops.size() > 0);
            bcb.emitABC(LOP_CONCAT, getRegister(insnOp), getRegInput(insn, 0), getRegInput(insn, insn.ops.size() - 1));
            break;

        case LOP_NOT:
        case LOP_MINUS:
        case LOP_LENGTH:
            bcb.emitABC(insn.op, getRegister(insnOp), getRegInput(insn, 0), 0);
            break;

        case LOP_NEWTABLE:
            bcb.emitABC(LOP_NEWTABLE, getRegister(insnOp), getImmInt(insn, 0), 0);
            bcb.emitAux(getImmInt(insn, 1));
            break;

        case LOP_DUPTABLE:
            bcb.emitAD(LOP_DUPTABLE, getRegister(insnOp), getVmConstInputD(insn, 0));
            break;

        case LOP_SETLIST:
            LUAU_ASSERT(insn.ops.size() > 2);
            bcb.emitABC(LOP_SETLIST, getRegInput(insn, 2), getRegInput(insn, 3), getImmInt(insn, 1) + 1);
            bcb.emitAux(getImmInt(insn, 0));
            break;

        case LOP_FORNPREP:
            recordJump(insn, 3);
            bcb.emitAD(LOP_FORNPREP, getRegInput(insn, 0), 0);
            break;

        case LOP_FORNLOOP:
            recordJump(insn, 3);
            bcb.emitAD(LOP_FORNLOOP, getRegInput(insn, 0), 0);
            break;

        case LOP_FORGPREP:
        case LOP_FORGPREP_NEXT:
        case LOP_FORGPREP_INEXT:
            recordJump(insn, 3);
            bcb.emitAD(insn.op, getRegInput(insn, 0), 0);
            break;

        case LOP_FORGLOOP:
            recordJump(insn, 5);
            bcb.emitAD(LOP_FORGLOOP, getRegInput(insn, 0), 0);
            bcb.emitAux(static_cast<uint32_t>(getImmBool(insn, 3)) << 31 | getImmInt(insn, 4));
            break;

        case LOP_FASTCALL:
            bcb.emitABC(LOP_FASTCALL, getImmInt(insn, 0), 0, getImmInt(insn, 1));
            break;

        case LOP_FASTCALL1:
            bcb.emitABC(LOP_FASTCALL1, getImmInt(insn, 0), getRegInput(insn, 1), getImmInt(insn, 2));
            break;

        case LOP_FASTCALL2:
            bcb.emitABC(LOP_FASTCALL2, getImmInt(insn, 0), getRegInput(insn, 1), getImmInt(insn, 3));
            bcb.emitAux(getRegInput(insn, 2));
            break;

        case LOP_FASTCALL2K:
            bcb.emitABC(LOP_FASTCALL2K, getImmInt(insn, 0), getRegInput(insn, 1), getImmInt(insn, 3));
            bcb.emitAux(getVmConstInputAux(insn, 2));
            break;

        case LOP_FASTCALL3:
            bcb.emitABC(LOP_FASTCALL3, getImmInt(insn, 0), getRegInput(insn, 1), getImmInt(insn, 4));
            bcb.emitAux(getRegInput(insn, 2) | static_cast<uint32_t>(getRegInput(insn, 3)) << 8);
            break;

        case LOP_GETVARARGS:
            LUAU_ASSERT(insn.ops.size() == 2 && insn.ops[0].kind == BcOpKind::VmReg);
            bcb.emitABC(LOP_GETVARARGS, insn.ops[0].index, getImmInt(insn, 1) + 1, 0);
            break;

        case LOP_DUPCLOSURE:
            bcb.emitAD(LOP_DUPCLOSURE, getRegister(insnOp), getVmConstInputD(insn, 0));
            break;

        case LOP_PREPVARARGS:
            bcb.emitAD(LOP_PREPVARARGS, getImmInt(insn, 0), 0);
            break;

        case LOP_LOADKX:
            bcb.emitAD(LOP_LOADKX, getRegister(insnOp), 0);
            bcb.emitAux(getVmConstInputAux(insn, 0));
            break;

        case LOP_JUMPX:
            recordJump(insn, 0);
            bcb.emitE(LOP_JUMPX, 0);
            break;

        case LOP_COVERAGE:
            bcb.emitE(LOP_COVERAGE, getImmInt(insn, 0));
            break;

        case LOP_CAPTURE:
        {
            uint8_t captureType = getImmInt(insn, 0);
            if (captureType == LCT_VAL || captureType == LCT_REF)
                bcb.emitABC(LOP_CAPTURE, captureType, getRegInput(insn, 1), getImmInt(insn, 2));
            else
                bcb.emitABC(LOP_CAPTURE, captureType, getUpvalInput(insn, 1), getImmInt(insn, 2));
            break;
        }

        case LOP_SUBRK:
        case LOP_DIVRK:
            bcb.emitABC(insn.op, getRegister(insnOp), getVmConstInputABC(insn, 0), getRegInput(insn, 1));
            break;

        case LOP_JUMPXEQKNIL:
            recordJump(insn, 2);
            bcb.emitAD(LOP_JUMPXEQKNIL, getRegInput(insn, 0), 0);
            bcb.emitAux(static_cast<uint32_t>(getImmBool(insn, 1)) << 31);
            break;

        case LOP_JUMPXEQKB:
            recordJump(insn, 2);
            bcb.emitAD(LOP_JUMPXEQKB, getRegInput(insn, 0), 0);
            bcb.emitAux(static_cast<uint32_t>(getImmBool(insn, 1)) << 31 | static_cast<uint32_t>(getImmBool(insn, 3)));
            break;

        case LOP_JUMPXEQKN:
        case LOP_JUMPXEQKS:
            recordJump(insn, 2);
            bcb.emitAD(insn.op, getRegInput(insn, 0), 0);
            bcb.emitAux(static_cast<uint32_t>(getImmBool(insn, 1)) << 31 | getVmConstInputAux(insn, 3));
            break;

        case LOP_IDIV:
            bcb.emitABC(LOP_IDIV, getRegister(insnOp), getRegInput(insn, 0), getRegInput(insn, 1));
            break;

        case LOP_IDIVK:
            bcb.emitABC(LOP_IDIVK, getRegister(insnOp), getRegInput(insn, 0), getVmConstInputABC(insn, 1));
            break;

        case LOP_NEWCLASSMEMBER:
            LUAU_ASSERT(FFlag::DebugLuauUserDefinedClasses);
            bcb.emitABC(LOP_NEWCLASSMEMBER, getRegInput(insn, 0), 0, getRegInput(insn, 1));
            bcb.emitAux(getVmConstInputAux(insn, 2));
            break;

        case LOP_CMPPROTO:
            recordJump(insn, 2);
            bcb.emitAD(LOP_CMPPROTO, getRegInput(insn, 0), 0);
            bcb.emitAux(getImmInt(insn, 1));
            break;

        case LOP__COUNT:
            LUAU_UNREACHABLE();
        }
    }

    std::optional<BcOp> getFallthrough(BcBlock& block)
    {
        for (auto [ctrl, target] : block.successors)
            if (ctrl == BcBlockEdgeKind::Fallthrough)
                return {target};
        return {};
    }

    std::vector<uint32_t> emitBytecode()
    {
        std::vector<BcOp> schedule = reschedule();
        std::vector<uint32_t> insnsPC;
        insnsPC.resize(func.instructions.size());

        for (size_t i = 0; i < schedule.size(); i++)
        {
            BcOp blockOp = schedule[i];
            BcBlock& block = func.blockOp(blockOp);
            std::optional<BcOp> fallthrough = getFallthrough(block);
            if (fallthrough && *fallthrough != func.exitBlock && (i + 1 >= schedule.size() || *fallthrough != schedule[i + 1]))
            {
                BcJump jump = BcJump<VmConst>::create(func);
                jump.setTarget(*fallthrough);
                jump.appendTo(blockOp);
                insnsPC.resize(func.instructions.size());
            }
            block.startpc = bcb.getDebugPC();
            for (BcOp op : block.ops)
            {
                LUAU_ASSERT(op.kind == BcOpKind::Inst);
                insnsPC[op.index] = bcb.getDebugPC();
                emitInstruction(op);
            }
        }

        for (auto& jump : jumps)
            patchJump(jump);

        // Serialization failed
        if (error)
            return {};

        return insnsPC;
    }
};

} // namespace Bytecode
} // namespace Luau
