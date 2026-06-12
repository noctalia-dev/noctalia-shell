// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/Bytecode.h"
#include "Luau/BytecodeBuilder.h"
#include "Luau/DenseHash.h"
#include "Luau/SmallVector.h"

#include <list>
#include <optional>
#include <vector>
#include <unordered_map>

#include <stdint.h>
#include <string.h>

namespace Luau
{
namespace Bytecode
{

using Instruction = uint32_t;
using Reg = uint8_t;

enum class BcOpKind : uint32_t
{
    None,

    // To reference a immediate value
    Imm,

    // To reference a result of a previous instruction
    Inst,

    // To reference a basic block in control flow
    Block,

    // Phi operand
    Phi,

    // Projection of multireturn call or variadic arguments
    Proj,

    // To reference a VM register
    VmReg,

    // To reference a VM constant
    VmConst,

    // To reference a VM upvalue
    VmUpvalue,

    // To reference a VM upvalue
    VmProto,
};

struct BcOp
{
    BcOpKind kind : 4;
    uint32_t index : 28;

    BcOp()
        : kind(BcOpKind::None)
        , index(0)
    {
    }

    BcOp(BcOpKind kind, uint32_t index)
        : kind(kind)
        , index(index)
    {
    }

    bool operator==(const BcOp& rhs) const
    {
        return kind == rhs.kind && index == rhs.index;
    }

    bool operator!=(const BcOp& rhs) const
    {
        return !(*this == rhs);
    }
};

static_assert(sizeof(BcOp) == 4);

struct BcOpHash
{
    size_t operator()(const BcOp& p) const
    {
        size_t res = 0;
        memcpy(&res, &p, sizeof(p));
        return res;
    }
};

using RegMap = std::unordered_map<BcOp, Reg, BcOpHash>;

enum class BcImmKind : uint8_t
{
    Boolean,
    Int,
    Import
};

struct BcImm
{
    BcImmKind kind;

    union
    {
        bool valueBoolean;
        int32_t valueInt;
        uint32_t valueImport;
    };
};

enum class BcVmConstKind : uint8_t
{
    Nil,
    Boolean,
    Number,
    Vector,
    String,
    Import,
    Table,
    Closure,
    Integer
};

struct BcVmConst
{
    BcVmConstKind kind;

    union
    {
        bool valueBoolean;
        double valueNumber;
        float valueVector[4];
        std::string_view valueString;
        uint32_t valueImport;
        uint32_t valueTable;
        uint32_t valueClosure;
        int64_t valueInteger;
    };

    BcVmConst()
        : kind(BcVmConstKind::Nil)
        , valueBoolean(0)
    {
    }
};

using BcOps = SmallVector<BcOp, 4>;

struct BcInst
{
    LuauOpcode op;
    BcOp block;

    // Operands
    BcOps ops;

    uint32_t lastUse = 0;
    uint32_t useCount = 0;
    uint32_t line = 0;
};

// When IrInst operands are used, current instruction index is often required to track lifetime
inline constexpr uint32_t kInvalidInstIdx = ~0u;

struct BcInstHash
{
    static const uint32_t m = 0x5bd1e995;
    static const int r = 24;

    static uint32_t mix(uint32_t h, uint32_t k)
    {
        // MurmurHash2 step
        k *= m;
        k ^= k >> r;
        k *= m;

        h *= m;
        h ^= k;

        return h;
    }

    static uint32_t mix(uint32_t h, BcOp op)
    {
        static_assert(sizeof(op) == sizeof(uint32_t));
        uint32_t k;
        memcpy(&k, &op, sizeof(op));

        return mix(h, k);
    }

    size_t operator()(const BcInst& key) const
    {
        // MurmurHash2 unrolled
        uint32_t h = 25;

        h = mix(h, uint32_t(key.op));
        for (size_t i = 0; i < 7; i++)
            h = mix(h, i < uint32_t(key.ops.size()) ? key.ops[i] : BcOp{});

        // MurmurHash2 tail
        h ^= h >> 13;
        h *= m;
        h ^= h >> 15;

        return h;
    }
};

struct BcInstEq
{
    bool operator()(const BcInst& a, const BcInst& b) const
    {
        if (a.op != b.op || a.ops.size() != b.ops.size())
            return false;
        for (size_t i = 0; i < a.ops.size(); i++)
            if (a.ops[i] != b.ops[i])
                return false;
        return true;
    }
};

inline constexpr uint32_t kBlockNoStartPc = ~0u;

enum BcBlockEdgeKind
{
    Branch,
    Fallthrough,
    Loop
};

struct BcBlockEdge
{
    BcBlockEdgeKind kind;
    BcOp target;
};

using BcEdges = SmallVector<BcBlockEdge, 2>;

enum BcBlockFlag
{
    Dead = 1 << 0
};

struct BcBlock
{
    uint8_t flags = 0;
    uint32_t useCount = 0;

    std::list<BcOp> ops;
    BcEdges successors;
    BcEdges predecessors;

    uint32_t sortkey = ~0u;
    uint32_t chainkey = 0;

    // Bytecode PC position at which the block was generated
    uint32_t startpc = kBlockNoStartPc;

    void appendInstruction(BcOp inst)
    {
        LUAU_ASSERT(inst.kind == BcOpKind::Inst);
        ops.push_back(inst);
    }
};

struct BcPhi
{
    BcOps ops;
};

struct BcProj
{
    BcOp op;
    uint32_t index;
};

struct TypedLocal
{
    LuauBytecodeType type;
    uint8_t reg;
    uint32_t startpc;
    uint32_t endpc;
};

struct DebugLocal
{
    std::string_view varname;
    uint8_t reg;
    uint32_t startpc;
    uint32_t endpc;
};

template<typename T>
struct BcRef
{
    std::vector<T>& vec;
    BcOp op;

    T* operator->()
    {
        LUAU_ASSERT(op.index < vec.size());
        return &vec[op.index];
    }

    T& operator*()
    {
        LUAU_ASSERT(op.index < vec.size());
        return vec[op.index];
    }
};

template<typename VmConst>
struct BcFunction
{
    uint8_t maxstacksize;
    uint8_t numparams;
    uint8_t nups;
    bool is_vararg;
    uint8_t flags;

    std::vector<BcBlock> blocks;
    std::vector<BcInst> instructions;
    std::vector<VmConst> constants;
    std::vector<BcImm> immediates;
    std::vector<BcPhi> phis;
    std::vector<BcProj> projections;
    std::vector<BytecodeBuilder::TableShape> tableShapes;

    BcOp entryBlock;
    BcOp exitBlock;

    std::string typeInfo;
    std::vector<LuauBytecodeType> upvalueTypes;
    std::vector<TypedLocal> localTypes;
    std::vector<uint32_t> protos;

    std::string debugname;
    uint32_t linedefined;
    std::vector<std::string_view> upvalueNames;
    std::vector<DebugLocal> locals;

    RegMap regs;

    BcOp addBlock()
    {
        blocks.emplace_back(BcBlock{});
        return BcOp{BcOpKind::Block, static_cast<uint32_t>(blocks.size() - 1)};
    }

    BcOp addInst()
    {
        instructions.emplace_back(BcInst{});
        return BcOp{BcOpKind::Inst, static_cast<uint32_t>(instructions.size() - 1)};
    }

    BcOp addPhi()
    {
        phis.emplace_back(BcPhi{});
        return BcOp{BcOpKind::Phi, static_cast<uint32_t>(phis.size() - 1)};
    }

    BcOp addProj(BcOp op, uint32_t index)
    {
        projections.emplace_back(BcProj{op, index});
        return BcOp{BcOpKind::Proj, static_cast<uint32_t>(projections.size() - 1)};
    }

    BcBlock& blockOp(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Block);
        return blocks[op.index];
    }

    BcInst& instOp(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Inst);
        return instructions[op.index];
    }

    BcInst* asInstOp(BcOp op)
    {
        if (op.kind == BcOpKind::Inst)
            return &instructions[op.index];

        return nullptr;
    }

    BcImm& immOp(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Imm);
        return immediates[op.index];
    }

    VmConst& constOp(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::VmConst);
        return constants[op.index];
    }

    BcPhi& phiOp(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Phi);
        return phis[op.index];
    }

    BcProj& projOp(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Proj);
        return projections[op.index];
    }

    uint32_t getBlockIndex(const BcBlock& block) const
    {
        // Can only be called with blocks from our vector
        LUAU_ASSERT(&block >= blocks.data() && &block <= blocks.data() + blocks.size());
        return uint32_t(&block - blocks.data());
    }

    uint32_t getInstIndex(const BcInst& inst) const
    {
        // Can only be called with instructions from our vector
        LUAU_ASSERT(&inst >= instructions.data() && &inst <= instructions.data() + instructions.size());
        return uint32_t(&inst - instructions.data());
    }

    BcOp addImm(BcImmKind kind)
    {
        BcImm imm{kind};
        imm.valueInt = 0;
        immediates.emplace_back(imm);
        return BcOp{BcOpKind::Imm, static_cast<uint32_t>(immediates.size() - 1)};
    }

    BcRef<BcBlock> block(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Block);
        return {blocks, op};
    }

    BcRef<BcInst> inst(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Inst);
        return {instructions, op};
    }

    template<typename T>
    T as(BcOp op)
    {
        BcRef<BcInst> insn = inst(op);
        LUAU_ASSERT(insn->op == T::opcode);

        return T{*this, insn};
    }

    BcRef<BcImm> imm(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Imm);
        return {immediates, op};
    }

    BcRef<BcPhi> phi(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Phi);
        return {phis, op};
    }

    BcRef<BcProj> proj(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::Proj);
        return {projections, op};
    }

    BcRef<VmConst> vmConst(BcOp op)
    {
        LUAU_ASSERT(op.kind == BcOpKind::VmConst);
        return {constants, op};
    }
};

using CompTimeBcFunction = BcFunction<BcVmConst>;

std::optional<CompTimeBcFunction> fromFunctionBytecode(std::string bytecode, std::vector<std::string_view>& strings);
std::string toFunctionBytecode(CompTimeBcFunction& func);
std::string toFunctionBytecode(BytecodeBuilder& builder, CompTimeBcFunction& func);

} // namespace Bytecode
} // namespace Luau
