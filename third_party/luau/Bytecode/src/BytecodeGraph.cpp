#include "Luau/BytecodeBuilder.h"
#include "Luau/BytecodeGraph.h"
#include "Luau/BytecodeUtils.h"
#include "Luau/BytecodeWire.h"

#include "BytecodeGraphParser.h"
#include "BytecodeGraphSerializer.h"

#include <unordered_set>
#include <algorithm>

LUAU_FASTFLAG(DebugLuauUserDefinedClasses)

namespace Luau
{
namespace Bytecode
{

static std::string_view readString(std::vector<std::string_view>& strings, const char* data, size_t& offset)
{
    uint32_t stringId = readVarInt(data, offset);
    LUAU_ASSERT(stringId <= strings.size());
    if (stringId == 0)
        return "";
    return strings[stringId - 1];
}

std::optional<CompTimeBcFunction> fromFunctionBytecode(std::string bytecode, std::vector<std::string_view>& strings)
{
    CompTimeBcFunction fn;
    size_t offset = 0;
    const char* data = bytecode.data();
    fn.maxstacksize = read<uint8_t>(data, offset);
    fn.numparams = read<uint8_t>(data, offset);
    fn.nups = read<uint8_t>(data, offset);
    fn.is_vararg = read<uint8_t>(data, offset);
    fn.flags = read<uint8_t>(data, offset);

    uint32_t typesSize = readVarInt(data, offset);
    if (typesSize > 0)
    {
        uint32_t typeInfoSize = readVarInt(data, offset);
        uint32_t typedUpvalSize = readVarInt(data, offset);
        uint32_t typedLocalSize = readVarInt(data, offset);
        fn.typeInfo = bytecode.substr(offset, typeInfoSize);
        offset += typeInfoSize;

        fn.upvalueTypes.resize(typedUpvalSize);
        for (uint32_t i = 0; i < typedUpvalSize; i++)
            fn.upvalueTypes[i] = static_cast<LuauBytecodeType>(read<uint8_t>(data, offset));

        fn.localTypes.resize(typedLocalSize);
        for (uint32_t i = 0; i < typedLocalSize; i++)
        {
            LuauBytecodeType type = static_cast<LuauBytecodeType>(read<uint8_t>(data, offset));
            uint8_t reg = read<uint8_t>(data, offset);
            uint32_t startpc = readVarInt(data, offset);
            uint32_t endpc = startpc + readVarInt(data, offset);
            fn.localTypes[i] = {type, reg, startpc, endpc};
        }
    }

    // store pointer to bytecode
    int32_t codesize = readVarInt(data, offset);
    const Instruction* code = reinterpret_cast<const Instruction*>(data + offset);

    offset += codesize * sizeof(Instruction);

    // read constants
    const uint32_t sizek = readVarInt(data, offset);
    fn.constants.resize(sizek);
    for (uint32_t i = 0; i < sizek; i++)
    {
        uint8_t constType = read<uint8_t>(data, offset);
        switch (constType)
        {
        case LBC_CONSTANT_NIL:
            fn.constants[i].kind = BcVmConstKind::Nil;
            break;

        case LBC_CONSTANT_BOOLEAN:
        {
            fn.constants[i].kind = BcVmConstKind::Boolean;
            fn.constants[i].valueBoolean = read<uint8_t>(data, offset);
            break;
        }

        case LBC_CONSTANT_NUMBER:
        {
            fn.constants[i].kind = BcVmConstKind::Number;
            fn.constants[i].valueNumber = read<double>(data, offset);
            break;
        }

        case LBC_CONSTANT_VECTOR:
        {
            fn.constants[i].kind = BcVmConstKind::Vector;
            fn.constants[i].valueVector[0] = read<float>(data, offset);
            fn.constants[i].valueVector[1] = read<float>(data, offset);
            fn.constants[i].valueVector[2] = read<float>(data, offset);
            fn.constants[i].valueVector[3] = read<float>(data, offset);
            break;
        }

        case LBC_CONSTANT_STRING:
        {
            fn.constants[i].kind = BcVmConstKind::String;
            fn.constants[i].valueString = readString(strings, data, offset);
            break;
        }

        case LBC_CONSTANT_IMPORT:
        {
            fn.constants[i].kind = BcVmConstKind::Import;
            fn.constants[i].valueImport = read<uint32_t>(data, offset);
            break;
        }

        case LBC_CONSTANT_TABLE:
        case LBC_CONSTANT_TABLE_WITH_CONSTANTS:
        {
            fn.constants[i].kind = BcVmConstKind::Table;
            fn.constants[i].valueTable = uint32_t(fn.tableShapes.size());

            BytecodeBuilder::TableShape shape;
            shape.length = readVarInt(data, offset);
            shape.hasConstants = constType == LBC_CONSTANT_TABLE_WITH_CONSTANTS;

            for (uint32_t i = 0; i < shape.length; ++i)
            {
                uint32_t key = readVarInt(data, offset);
                LUAU_ASSERT(key < sizek);
                shape.keys[i] = key;
                if (shape.hasConstants)
                {
                    int32_t value = read<int32_t>(data, offset);
                    LUAU_ASSERT(value < static_cast<int32_t>(sizek));
                    shape.constants[i] = value;
                }
            }
            fn.tableShapes.push_back(shape);
            break;
        }

        case LBC_CONSTANT_CLOSURE:
        {
            fn.constants[i].kind = BcVmConstKind::Closure;
            fn.constants[i].valueClosure = readVarInt(data, offset);
            break;
        }

        case LBC_CONSTANT_INTEGER:
        {
            fn.constants[i].kind = BcVmConstKind::Integer;
            bool isNegative = read<uint8_t>(data, offset);
            uint64_t magnitude = readVarInt64(data, offset);
            fn.constants[i].valueInteger = isNegative ? (int64_t)(~magnitude + 1) : (int64_t)magnitude;
            break;
        }
        default:
            LUAU_ASSERT(!"Unknown constant type!");
        }
    }

    uint32_t psize = readVarInt(data, offset);
    fn.protos.resize(psize);
    for (uint32_t i = 0; i < psize; i++)
        fn.protos[i] = readVarInt(data, offset);

    fn.linedefined = readVarInt(data, offset);
    fn.debugname = readString(strings, data, offset);

    uint8_t lineinfo = read<uint8_t>(data, offset);
    std::vector<uint32_t> lines;

    if (lineinfo != 0)
    {
        uint8_t linegaplog2 = read<uint8_t>(data, offset);

        int intervals = ((codesize - 1) >> linegaplog2) + 1;
        int absoffset = (codesize + 3) & ~3;

        const int sizelineinfo = absoffset + intervals * sizeof(int);
        std::vector<uint8_t> lineinfo;
        lineinfo.resize(sizelineinfo);
        int* abslineinfo = reinterpret_cast<int*>(lineinfo.data() + absoffset);

        uint8_t lastoffset = 0;
        for (int i = 0; i < codesize; i++)
        {
            lastoffset += read<uint8_t>(data, offset);
            lineinfo[i] = lastoffset;
        }

        int lastline = 0;
        for (int i = 0; i < intervals; i++)
        {
            lastline += read<int32_t>(data, offset);
            abslineinfo[i] = lastline;
        }
        lines.resize(codesize);
        for (int i = 0; i < codesize; i++)
            lines[i] = abslineinfo[i >> linegaplog2] + lineinfo[i];
    }

    uint8_t debuginfo = read<uint8_t>(data, offset);

    if (debuginfo != 0)
    {
        const int sizelocvars = readVarInt(data, offset);
        fn.locals.resize(sizelocvars);

        for (int i = 0; i < sizelocvars; i++)
        {
            std::string_view varname = readString(strings, data, offset);
            uint32_t startpc = readVarInt(data, offset);
            uint32_t endpc = readVarInt(data, offset);
            uint8_t reg = read<uint8_t>(data, offset);
            fn.locals[i] = {varname, reg, startpc, endpc};
        }

        const int sizeupvalues = readVarInt(data, offset);
        fn.upvalueNames.resize(sizeupvalues);

        for (int i = 0; i < sizeupvalues; i++)
            fn.upvalueNames[i] = readString(strings, data, offset);
    }

    std::vector<uint32_t> insnsPC;
    BytecodeGraphParser<BcVmConst> graphParser(fn);
    if (!graphParser.rebuildGraph(code, codesize, lines, insnsPC))
        return {};

    for (TypedLocal& l : fn.localTypes)
    {
        l.startpc = l.startpc < insnsPC.size() ? insnsPC[l.startpc] : codesize;
        l.endpc = l.endpc < insnsPC.size() ? insnsPC[l.endpc] : codesize;
    }

    for (DebugLocal& l : fn.locals)
    {
        l.startpc = l.startpc < insnsPC.size() ? insnsPC[l.startpc] : codesize;
        l.endpc = l.endpc < insnsPC.size() ? insnsPC[l.endpc] : codesize;
    }

    return {fn};
}

struct CompTimeBytecodeGraphSerializer : public BytecodeGraphSerializer<BcVmConst>
{
    std::vector<uint16_t>& consts;
    CompTimeBytecodeGraphSerializer(BytecodeBuilder& bcb, CompTimeBcFunction& fn, std::vector<uint16_t>& consts)
        : BytecodeGraphSerializer<BcVmConst>(bcb, fn)
        , consts(consts)
    {
    }

    uint32_t getVmConstInputRaw(BcInst& insn, uint8_t index) override
    {
        uint32_t cid = BytecodeGraphSerializer<BcVmConst>::getVmConstInputRaw(insn, index);
        LUAU_ASSERT(cid < consts.size());
        return consts[cid];
    }
};

std::string toFunctionBytecode(BytecodeBuilder& bcb, CompTimeBcFunction& fn)
{
    uint32_t functionId = bcb.beginFunction(fn.numparams, fn.is_vararg);
    if (fn.debugname != "")
        bcb.setDebugFunctionName({fn.debugname.data(), fn.debugname.size()});
    bcb.setDebugFunctionLineDefined(fn.linedefined);
    bcb.setFunctionTypeInfo(fn.typeInfo);
    for (LuauBytecodeType t : fn.upvalueTypes)
        bcb.pushUpvalTypeInfo(t);
    for (auto& upval : fn.upvalueNames)
        bcb.pushDebugUpval({upval.data(), upval.size()});

    std::vector<uint16_t> consts;
    consts.reserve(fn.constants.size());
    for (auto& c : fn.constants)
    {
        switch (c.kind)
        {
        case BcVmConstKind::Nil:
            consts.push_back(bcb.addConstantNil());
            break;

        case BcVmConstKind::Boolean:
            consts.push_back(bcb.addConstantBoolean(c.valueBoolean));
            break;

        case BcVmConstKind::Number:
            consts.push_back(bcb.addConstantNumber(c.valueNumber));
            break;

        case BcVmConstKind::Vector:
            consts.push_back(bcb.addConstantVector(c.valueVector[0], c.valueVector[1], c.valueVector[2], c.valueVector[3]));
            break;

        case BcVmConstKind::String:
            consts.push_back(bcb.addConstantString({c.valueString.data(), c.valueString.size()}));
            break;

        case BcVmConstKind::Import:
            consts.push_back(bcb.addImport(c.valueImport));
            break;

        case BcVmConstKind::Table:
        {
            LUAU_ASSERT(c.valueTable < fn.tableShapes.size());
            consts.push_back(bcb.addConstantTable(fn.tableShapes[c.valueTable]));
            break;
        }

        case BcVmConstKind::Closure:
            consts.push_back(bcb.addConstantClosure(c.valueClosure));
            break;

        case BcVmConstKind::Integer:
            consts.push_back(bcb.addConstantInteger(c.valueInteger));
            break;
        }
    }

    for (auto fid : fn.protos)
        bcb.addChildFunction(fid);

    CompTimeBytecodeGraphSerializer serializer(bcb, fn, consts);
    std::vector<uint32_t> insnsPC = serializer.emitBytecode();

    for (auto& local : fn.localTypes)
    {
        uint32_t startpc = local.startpc < insnsPC.size() ? insnsPC[local.startpc] : bcb.getDebugPC();
        uint32_t endpc = local.endpc < insnsPC.size() ? insnsPC[local.endpc] : bcb.getDebugPC();
        bcb.pushLocalTypeInfo(local.type, local.reg, startpc, endpc);
    }
    for (auto& local : fn.locals)
    {
        uint32_t startpc = local.startpc < insnsPC.size() ? insnsPC[local.startpc] : bcb.getDebugPC();
        uint32_t endpc = local.endpc < insnsPC.size() ? insnsPC[local.endpc] : bcb.getDebugPC();
        bcb.pushDebugLocal({local.varname.data(), local.varname.size()}, local.reg, startpc, endpc);
    }

    bcb.foldJumps();

    bcb.expandJumps();

    bcb.endFunction(fn.maxstacksize, fn.nups, fn.flags);

    if (serializer.error)
        return "";

    return bcb.getFunctionData(functionId);
}

std::string toFunctionBytecode(CompTimeBcFunction& fn)
{
    BytecodeBuilder bcb;
    return toFunctionBytecode(bcb, fn);
}

}; // namespace Bytecode
}; // namespace Luau
