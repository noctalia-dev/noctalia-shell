// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "Luau/BytecodeBuilder.h"

#include "Luau/BytecodeUtils.h"
#include "Luau/StringUtils.h"

#include <algorithm>
#include <string.h>
#include <climits>

LUAU_FASTFLAG(LuauCompileDuptableConstantPack2)
LUAU_FASTFLAG(LuauIntegerType)
LUAU_FASTFLAGVARIABLE(LuauCompileUdataDirect)

namespace Luau
{

static_assert(LBC_VERSION_TARGET >= LBC_VERSION_MIN && LBC_VERSION_TARGET <= LBC_VERSION_MAX, "Invalid bytecode version setup");
static_assert(LBC_VERSION_MAX <= 127, "Bytecode version should be 7-bit so that we can extend the serialization to use varint transparently");

static const uint32_t kMaxConstantCount = 1 << 23;
static const uint32_t kMaxClosureCount = 1 << 15;

static const int kMaxJumpDistance = 1 << 23;

static int log2(int v)
{
    LUAU_ASSERT(v);

    int r = 0;

    while (v >= (2 << r))
        r++;

    return r;
}

static void writeByte(std::string& ss, unsigned char value)
{
    ss.append(reinterpret_cast<const char*>(&value), sizeof(value));
}

static void writeInt(std::string& ss, int value)
{
    ss.append(reinterpret_cast<const char*>(&value), sizeof(value));
}

static void writeFloat(std::string& ss, float value)
{
    ss.append(reinterpret_cast<const char*>(&value), sizeof(value));
}

static void writeDouble(std::string& ss, double value)
{
    ss.append(reinterpret_cast<const char*>(&value), sizeof(value));
}

static void writeVarInt(std::string& ss, uint64_t value)
{
    do
    {
        writeByte(ss, (value & 127) | ((value > 127) << 7));
        value >>= 7;
    } while (value);
}

inline bool isJumpD(LuauOpcode op)
{
    switch (op)
    {
    case LOP_JUMP:
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
    case LOP_FORGPREP:
    case LOP_FORGLOOP:
    case LOP_FORGPREP_INEXT:
    case LOP_FORGPREP_NEXT:
    case LOP_JUMPBACK:
    case LOP_JUMPXEQKNIL:
    case LOP_JUMPXEQKB:
    case LOP_JUMPXEQKN:
    case LOP_JUMPXEQKS:
        return true;

    default:
        return false;
    }
}

inline bool isSkipC(LuauOpcode op)
{
    switch (op)
    {
    case LOP_LOADB:
        return true;

    default:
        return false;
    }
}

inline bool isFastCall(LuauOpcode op)
{
    switch (op)
    {
    case LOP_FASTCALL:
    case LOP_FASTCALL1:
    case LOP_FASTCALL2:
    case LOP_FASTCALL2K:
    case LOP_FASTCALL3:
        return true;

    default:
        return false;
    }
}

static int getJumpTarget(uint32_t insn, uint32_t pc)
{
    LuauOpcode op = LuauOpcode(LUAU_INSN_OP(insn));

    if (isJumpD(op))
        return int(pc + LUAU_INSN_D(insn) + 1);
    else if (isFastCall(op))
        return int(pc + LUAU_INSN_C(insn) + 2);
    else if (isSkipC(op) && LUAU_INSN_C(insn))
        return int(pc + LUAU_INSN_C(insn) + 1);
    else if (op == LOP_JUMPX)
        return int(pc + LUAU_INSN_E(insn) + 1);
    else
        return -1;
}

bool BytecodeBuilder::StringRef::operator==(const StringRef& other) const
{
    return (data && other.data) ? (length == other.length && memcmp(data, other.data, length) == 0) : (data == other.data);
}

bool BytecodeBuilder::TableShape::operator==(const TableShape& other) const
{
    if (!FFlag::LuauCompileDuptableConstantPack2)
    {

        return length == other.length && memcmp(keys, other.keys, length * sizeof(keys[0])) == 0;
    }
    else
    {
        bool equal = length == other.length && memcmp(keys, other.keys, length * sizeof(keys[0])) == 0 && hasConstants == other.hasConstants;

        if (hasConstants)
        {
            equal = equal && memcmp(constants, other.constants, length * sizeof(constants[0])) == 0;
        }

        return equal;
    }
}

size_t BytecodeBuilder::StringRefHash::operator()(const StringRef& v) const
{
    return hashRange(v.data, v.length);
}

size_t BytecodeBuilder::ConstantKeyHash::operator()(const ConstantKey& key) const
{
    if (key.type == Constant::Type_Vector)
    {
        uint32_t i[4];
        static_assert(sizeof(key.value) + sizeof(key.extra) == sizeof(i), "Expecting vector to have four 32-bit components");
        memcpy(i, &key.value, sizeof(i));

        // scramble bits to make sure that integer coordinates have entropy in lower bits
        i[0] ^= i[0] >> 17;
        i[1] ^= i[1] >> 17;
        i[2] ^= i[2] >> 17;
        i[3] ^= i[3] >> 17;

        // Optimized Spatial Hashing for Collision Detection of Deformable Objects
        uint32_t h = (i[0] * 73856093) ^ (i[1] * 19349663) ^ (i[2] * 83492791) ^ (i[3] * 39916801);

        return size_t(h);
    }
    else
    {
        // finalizer from MurmurHash64B
        const uint32_t m = 0x5bd1e995;

        uint32_t h1 = uint32_t(key.value);
        uint32_t h2 = uint32_t(key.value >> 32) ^ (key.type * m);

        h1 ^= h2 >> 18;
        h1 *= m;
        h2 ^= h1 >> 22;
        h2 *= m;
        h1 ^= h2 >> 17;
        h1 *= m;
        h2 ^= h1 >> 19;
        h2 *= m;

        // ... truncated to 32-bit output (normally hash is equal to (uint64_t(h1) << 32) | h2, but we only really need the lower 32-bit half)
        return size_t(h2);
    }
}

size_t BytecodeBuilder::TableShapeHash::operator()(const TableShape& v) const
{
    // FNV-1a inspired hash (note that we feed integers instead of bytes)
    uint32_t hash = 2166136261;

    for (size_t i = 0; i < v.length; ++i)
    {
        hash ^= v.keys[i];
        hash *= 16777619;

        if (FFlag::LuauCompileDuptableConstantPack2 && v.hasConstants)
        {
            hash ^= v.constants[i];
            hash *= 16777619;
        }
    }

    return hash;
}

BytecodeBuilder::BytecodeBuilder(BytecodeEncoder* encoder)
    : constantMap({Constant::Type_Nil, ~0ull})
    , tableShapeMap(TableShape())
    , protoMap(~0u)
    , stringTable({nullptr, 0})
    , encoder(encoder)
{
    LUAU_ASSERT(stringTable.find(StringRef{"", 0}) == nullptr);

    // preallocate some buffers that are very likely to grow anyway; this works around std::vector's inefficient growth policy for small arrays
    insns.reserve(32);
    lines.reserve(32);
    constants.reserve(16);
    protos.reserve(16);
    functions.reserve(8);
}

uint32_t BytecodeBuilder::beginFunction(uint8_t numparams, bool isvararg)
{
    LUAU_ASSERT(currentFunction == ~0u);

    uint32_t id = uint32_t(functions.size());

    Function func;
    func.numparams = numparams;
    func.isvararg = isvararg;

    functions.push_back(func);

    currentFunction = id;

    hasLongJumps = false;
    debugLine = 0;

    return id;
}

void BytecodeBuilder::endFunction(uint8_t maxstacksize, uint8_t numupvalues, uint8_t flags)
{
    LUAU_ASSERT(currentFunction != ~0u);

    Function& func = functions[currentFunction];

    func.maxstacksize = maxstacksize;
    func.numupvalues = numupvalues;

#ifdef LUAU_ASSERTENABLED
    validate();
#endif

    // this call is indirect to make sure we only gain link time dependency on dumpCurrentFunction when needed
    if (dumpFunctionPtr)
        func.dump = (this->*dumpFunctionPtr)(func.dumpinstoffs);

    // very approximate: 4 bytes per instruction for code, 1 byte for debug line, and 1-2 bytes for aux data like constants plus overhead
    func.data.reserve(32 + insns.size() * 7);

    if (encoder)
        encoder->encode(insns.data(), insns.size());

    writeFunction(func.data, currentFunction, flags);

    currentFunction = ~0u;

    totalInstructionCount += insns.size();
    insns.clear();
    lines.clear();
    constants.clear();
    protos.clear();
    jumps.clear();
    tableShapes.clear();

    debugLocals.clear();
    debugUpvals.clear();

    typedLocals.clear();
    typedUpvals.clear();

    constantMap.clear();
    tableShapeMap.clear();
    protoMap.clear();

    debugRemarks.clear();
    debugRemarkBuffer.clear();
}

void BytecodeBuilder::setMainFunction(uint32_t fid)
{
    LUAU_ASSERT(fid < functions.size());

    mainFunction = fid;
}

int32_t BytecodeBuilder::addConstant(const ConstantKey& key, const Constant& value)
{
    if (int32_t* cache = constantMap.find(key))
        return *cache;

    uint32_t id = uint32_t(constants.size());

    if (id >= kMaxConstantCount)
        return -1;

    constantMap[key] = int32_t(id);
    constants.push_back(value);

    return int32_t(id);
}

unsigned int BytecodeBuilder::addStringTableEntry(StringRef value)
{
    unsigned int& index = stringTable[value];

    // note: bytecode serialization format uses 1-based table indices, 0 is reserved to mean nil
    if (index == 0)
    {
        index = uint32_t(stringTable.size());

        if ((dumpFlags & Dump_Code) != 0)
            debugStrings.push_back(value);
    }

    return index;
}

const char* BytecodeBuilder::tryGetUserdataTypeName(LuauBytecodeType type) const
{
    unsigned index = unsigned((type & ~LBC_TYPE_OPTIONAL_BIT) - LBC_TYPE_TAGGED_USERDATA_BASE);

    if (index < userdataTypes.size())
        return userdataTypes[index].name.c_str();

    return nullptr;
}

int32_t BytecodeBuilder::addConstantNil()
{
    Constant c = {Constant::Type_Nil};

    ConstantKey k = {Constant::Type_Nil};
    return addConstant(k, c);
}

int32_t BytecodeBuilder::addConstantBoolean(bool value)
{
    Constant c = {Constant::Type_Boolean};
    c.valueBoolean = value;

    ConstantKey k = {Constant::Type_Boolean, value};
    return addConstant(k, c);
}

int32_t BytecodeBuilder::addConstantNumber(double value)
{
    Constant c = {Constant::Type_Number};
    c.valueNumber = value;

    ConstantKey k = {Constant::Type_Number};
    static_assert(sizeof(k.value) == sizeof(value), "Expecting double to be 64-bit");
    memcpy(&k.value, &value, sizeof(value));

    return addConstant(k, c);
}

int32_t BytecodeBuilder::addConstantInteger(int64_t value)
{
    Constant c = {Constant::Type_Integer};
    c.valueInteger64 = value;

    ConstantKey k = {Constant::Type_Integer};
    static_assert(sizeof(k.value) == sizeof(value), "Expecting integer to be 64-bit");
    memcpy(&k.value, &value, sizeof(value));

    return addConstant(k, c);
}

int32_t BytecodeBuilder::addConstantVector(float x, float y, float z, float w)
{
    Constant c = {Constant::Type_Vector};
    c.valueVector[0] = x;
    c.valueVector[1] = y;
    c.valueVector[2] = z;
    c.valueVector[3] = w;

    ConstantKey k = {Constant::Type_Vector};
    static_assert(
        sizeof(k.value) == sizeof(x) + sizeof(y) && sizeof(k.extra) == sizeof(z) + sizeof(w), "Expecting vector to have four 32-bit components"
    );
    memcpy(&k.value, &x, sizeof(x));
    memcpy((char*)&k.value + sizeof(x), &y, sizeof(y));
    memcpy(&k.extra, &z, sizeof(z));
    memcpy((char*)&k.extra + sizeof(z), &w, sizeof(w));

    return addConstant(k, c);
}

int32_t BytecodeBuilder::addConstantString(StringRef value)
{
    unsigned int index = addStringTableEntry(value);

    Constant c = {Constant::Type_String};
    c.valueString = index;

    ConstantKey k = {Constant::Type_String, index};

    return addConstant(k, c);
}

int32_t BytecodeBuilder::addImport(uint32_t iid)
{
    Constant c = {Constant::Type_Import};
    c.valueImport = iid;

    ConstantKey k = {Constant::Type_Import, iid};

    return addConstant(k, c);
}

int32_t BytecodeBuilder::addConstantTable(const TableShape& shape)
{
    if (int32_t* cache = tableShapeMap.find(shape))
        return *cache;

    uint32_t id = uint32_t(constants.size());

    if (id >= kMaxConstantCount)
        return -1;

    Constant value = {Constant::Type_Table};
    value.valueTable = uint32_t(tableShapes.size());

    tableShapeMap[shape] = int32_t(id);
    tableShapes.push_back(shape);
    constants.push_back(value);

    return int32_t(id);
}

int32_t BytecodeBuilder::addConstantClosure(uint32_t fid)
{
    Constant c = {Constant::Type_Closure};
    c.valueClosure = fid;

    ConstantKey k = {Constant::Type_Closure, fid};

    return addConstant(k, c);
}

int16_t BytecodeBuilder::addChildFunction(uint32_t fid)
{
    if (int16_t* cache = protoMap.find(fid))
        return *cache;

    uint32_t id = uint32_t(protos.size());

    if (id >= kMaxClosureCount)
        return -1;

    protoMap[fid] = int16_t(id);
    protos.push_back(fid);

    return int16_t(id);
}

void BytecodeBuilder::emitABC(LuauOpcode op, uint8_t a, uint8_t b, uint8_t c)
{
    uint32_t insn = uint32_t(op) | (a << 8) | (b << 16) | (c << 24);

    insns.push_back(insn);
    lines.push_back(debugLine);
}

void BytecodeBuilder::emitAD(LuauOpcode op, uint8_t a, int16_t d)
{
    uint32_t insn = uint32_t(op) | (a << 8) | (uint16_t(d) << 16);

    insns.push_back(insn);
    lines.push_back(debugLine);
}

void BytecodeBuilder::emitE(LuauOpcode op, int32_t e)
{
    uint32_t insn = uint32_t(op) | (uint32_t(e) << 8);

    insns.push_back(insn);
    lines.push_back(debugLine);
}

void BytecodeBuilder::emitAux(uint32_t aux)
{
    insns.push_back(aux);
    lines.push_back(debugLine);
}

void BytecodeBuilder::undoEmit(LuauOpcode op)
{
    LUAU_ASSERT(!insns.empty());
    LUAU_ASSERT((insns.back() & 0xff) == op);

    insns.pop_back();
    lines.pop_back();
}

size_t BytecodeBuilder::emitLabel()
{
    return insns.size();
}

bool BytecodeBuilder::patchJumpD(size_t jumpLabel, size_t targetLabel)
{
    LUAU_ASSERT(jumpLabel < insns.size());

    unsigned int jumpInsn = insns[jumpLabel];
    (void)jumpInsn;

    LUAU_ASSERT(isJumpD(LuauOpcode(LUAU_INSN_OP(jumpInsn))));
    LUAU_ASSERT(LUAU_INSN_D(jumpInsn) == 0);

    LUAU_ASSERT(targetLabel <= insns.size());

    int offset = int(targetLabel) - int(jumpLabel) - 1;

    if (int16_t(offset) == offset)
    {
        insns[jumpLabel] |= uint16_t(offset) << 16;
    }
    else if (abs(offset) < kMaxJumpDistance)
    {
        // our jump doesn't fit into 16 bits; we will need to repatch the bytecode sequence with jump trampolines, see expandJumps
        hasLongJumps = true;
    }
    else
    {
        return false;
    }

    jumps.push_back({uint32_t(jumpLabel), uint32_t(targetLabel)});
    return true;
}

bool BytecodeBuilder::patchSkipC(size_t jumpLabel, size_t targetLabel)
{
    LUAU_ASSERT(jumpLabel < insns.size());

    unsigned int jumpInsn = insns[jumpLabel];
    (void)jumpInsn;

    LUAU_ASSERT(isSkipC(LuauOpcode(LUAU_INSN_OP(jumpInsn))) || isFastCall(LuauOpcode(LUAU_INSN_OP(jumpInsn))));
    LUAU_ASSERT(LUAU_INSN_C(jumpInsn) == 0);

    int offset = int(targetLabel) - int(jumpLabel) - 1;

    if (uint8_t(offset) != offset)
    {
        return false;
    }

    insns[jumpLabel] |= offset << 24;
    return true;
}

void BytecodeBuilder::setFunctionTypeInfo(std::string value)
{
    functions[currentFunction].typeinfo = std::move(value);
}

void BytecodeBuilder::pushLocalTypeInfo(LuauBytecodeType type, uint8_t reg, uint32_t startpc, uint32_t endpc)
{
    TypedLocal local;
    local.type = type;
    local.reg = reg;
    local.startpc = startpc;
    local.endpc = endpc;

    typedLocals.push_back(local);
}

void BytecodeBuilder::pushUpvalTypeInfo(LuauBytecodeType type)
{
    TypedUpval upval;
    upval.type = type;

    typedUpvals.push_back(upval);
}

uint32_t BytecodeBuilder::addUserdataType(const char* name)
{
    UserdataType ty;

    ty.name = name;

    userdataTypes.push_back(std::move(ty));
    return uint32_t(userdataTypes.size() - 1);
}

void BytecodeBuilder::useUserdataType(uint32_t index)
{
    userdataTypes[index].used = true;
}

void BytecodeBuilder::setDebugFunctionName(StringRef name)
{
    unsigned int index = addStringTableEntry(name);

    functions[currentFunction].debugname = index;

    if (dumpFunctionPtr)
        functions[currentFunction].dumpname = std::string(name.data, name.length);
}

void BytecodeBuilder::setDebugFunctionLineDefined(int line)
{
    functions[currentFunction].debuglinedefined = line;
}

void BytecodeBuilder::setDebugLine(int line)
{
    debugLine = line;
}

void BytecodeBuilder::pushDebugLocal(StringRef name, uint8_t reg, uint32_t startpc, uint32_t endpc)
{
    unsigned int index = addStringTableEntry(name);

    DebugLocal local;
    local.name = index;
    local.reg = reg;
    local.startpc = startpc;
    local.endpc = endpc;

    debugLocals.push_back(local);
}

void BytecodeBuilder::pushDebugUpval(StringRef name)
{
    unsigned int index = addStringTableEntry(name);

    DebugUpval upval;
    upval.name = index;

    debugUpvals.push_back(upval);
}

size_t BytecodeBuilder::getInstructionCount() const
{
    return insns.size();
}

size_t BytecodeBuilder::getTotalInstructionCount() const
{
    return totalInstructionCount;
}

uint32_t BytecodeBuilder::getDebugPC() const
{
    return uint32_t(insns.size());
}

void BytecodeBuilder::addDebugRemark(const char* format, ...)
{
    if ((dumpFlags & Dump_Remarks) == 0)
        return;

    size_t offset = debugRemarkBuffer.size();

    va_list args;
    va_start(args, format);
    vformatAppend(debugRemarkBuffer, format, args);
    va_end(args);

    // we null-terminate all remarks to avoid storing remark length
    debugRemarkBuffer += '\0';

    debugRemarks.emplace_back(uint32_t(insns.size()), uint32_t(offset));
    dumpRemarks.emplace_back(debugLine, debugRemarkBuffer.c_str() + offset);
}

void BytecodeBuilder::finalize()
{
    LUAU_ASSERT(bytecode.empty());

    for (auto& ty : userdataTypes)
    {
        if (ty.used)
            ty.nameRef = addStringTableEntry(StringRef({ty.name.c_str(), ty.name.length()}));
    }

    // preallocate space for bytecode blob
    size_t capacity = 16;

    for (auto& p : stringTable)
        capacity += p.first.length + 2;

    for (const Function& func : functions)
        capacity += func.data.size();

    bytecode.reserve(capacity);

    // assemble final bytecode blob
    uint8_t version = getVersion();
    LUAU_ASSERT(version >= LBC_VERSION_MIN && version <= LBC_VERSION_MAX);

    bytecode = char(version);

    uint8_t typesversion = getTypeEncodingVersion();
    LUAU_ASSERT(typesversion >= LBC_TYPE_VERSION_MIN && typesversion <= LBC_TYPE_VERSION_MAX);
    writeByte(bytecode, typesversion);

    writeStringTable(bytecode);

    {
        // Write the mapping between used type name indices and their name
        for (uint32_t i = 0; i < uint32_t(userdataTypes.size()); i++)
        {
            if (userdataTypes[i].used)
            {
                writeByte(bytecode, i + 1);
                writeVarInt(bytecode, userdataTypes[i].nameRef);
            }
        }

        // 0 marks the end of the mapping
        writeByte(bytecode, 0);
    }

    writeVarInt(bytecode, uint32_t(functions.size()));

    for (const Function& func : functions)
        bytecode += func.data;

    LUAU_ASSERT(mainFunction < functions.size());
    writeVarInt(bytecode, mainFunction);
}

void BytecodeBuilder::writeFunction(std::string& ss, uint32_t id, uint8_t flags)
{
    LUAU_ASSERT(id < functions.size());
    const Function& func = functions[id];

    // header
    writeByte(ss, func.maxstacksize);
    writeByte(ss, func.numparams);
    writeByte(ss, func.numupvalues);
    writeByte(ss, func.isvararg);

    writeByte(ss, flags);

    if (!func.typeinfo.empty() || !typedUpvals.empty() || !typedLocals.empty())
    {
        // collect type info into a temporary string to know the overall size of type data
        tempTypeInfo.clear();
        writeVarInt(tempTypeInfo, uint32_t(func.typeinfo.size()));
        writeVarInt(tempTypeInfo, uint32_t(typedUpvals.size()));
        writeVarInt(tempTypeInfo, uint32_t(typedLocals.size()));

        tempTypeInfo.append(func.typeinfo);

        for (const TypedUpval& l : typedUpvals)
            writeByte(tempTypeInfo, l.type);

        for (const TypedLocal& l : typedLocals)
        {
            writeByte(tempTypeInfo, l.type);
            writeByte(tempTypeInfo, l.reg);
            writeVarInt(tempTypeInfo, l.startpc);
            LUAU_ASSERT(l.endpc >= l.startpc);
            writeVarInt(tempTypeInfo, l.endpc - l.startpc);
        }

        writeVarInt(ss, uint32_t(tempTypeInfo.size()));
        ss.append(tempTypeInfo);
    }
    else
    {
        writeVarInt(ss, 0);
    }

    // instructions
    writeVarInt(ss, uint32_t(insns.size()));

    for (uint32_t insn : insns)
        writeInt(ss, insn);

    // constants
    writeVarInt(ss, uint32_t(constants.size()));

    for (const Constant& c : constants)
    {
        switch (c.type)
        {
        case Constant::Type_Nil:
            writeByte(ss, LBC_CONSTANT_NIL);
            break;

        case Constant::Type_Boolean:
            writeByte(ss, LBC_CONSTANT_BOOLEAN);
            writeByte(ss, c.valueBoolean);
            break;

        case Constant::Type_Number:
            writeByte(ss, LBC_CONSTANT_NUMBER);
            writeDouble(ss, c.valueNumber);
            break;

        case Constant::Type_Integer:
            writeByte(ss, LBC_CONSTANT_INTEGER);
            if (c.valueInteger64 < 0)
            {
                writeByte(ss, 1);
                writeVarInt(ss, ~(uint64_t)c.valueInteger64 + 1);
            }
            else
            {
                writeByte(ss, 0);
                writeVarInt(ss, c.valueInteger64);
            }
            break;

        case Constant::Type_Vector:
            writeByte(ss, LBC_CONSTANT_VECTOR);
            writeFloat(ss, c.valueVector[0]);
            writeFloat(ss, c.valueVector[1]);
            writeFloat(ss, c.valueVector[2]);
            writeFloat(ss, c.valueVector[3]);
            break;

        case Constant::Type_String:
            writeByte(ss, LBC_CONSTANT_STRING);
            writeVarInt(ss, c.valueString);
            break;

        case Constant::Type_Import:
            writeByte(ss, LBC_CONSTANT_IMPORT);
            writeInt(ss, c.valueImport);
            break;

        case Constant::Type_Table:
        {
            const TableShape& shape = tableShapes[c.valueTable];
            if (FFlag::LuauCompileDuptableConstantPack2 && shape.hasConstants)
            {
                writeByte(ss, LBC_CONSTANT_TABLE_WITH_CONSTANTS);
                writeVarInt(ss, uint32_t(shape.length));
                for (unsigned int i = 0; i < shape.length; ++i)
                {
                    writeVarInt(ss, shape.keys[i]);
                    writeInt(ss, shape.constants[i]);
                }
            }
            else
            {
                writeByte(ss, LBC_CONSTANT_TABLE);
                writeVarInt(ss, uint32_t(shape.length));
                for (unsigned int i = 0; i < shape.length; ++i)
                    writeVarInt(ss, shape.keys[i]);
            }
            break;
        }

        case Constant::Type_Closure:
            writeByte(ss, LBC_CONSTANT_CLOSURE);
            writeVarInt(ss, c.valueClosure);
            break;

        default:
            LUAU_ASSERT(!"Unsupported constant type");
        }
    }

    // child protos
    writeVarInt(ss, uint32_t(protos.size()));

    for (uint32_t child : protos)
        writeVarInt(ss, child);

    // debug info
    writeVarInt(ss, func.debuglinedefined);
    writeVarInt(ss, func.debugname);

    bool hasLines = true;

    for (int line : lines)
        if (line == 0)
        {
            hasLines = false;
            break;
        }

    if (hasLines)
    {
        writeByte(ss, 1);

        writeLineInfo(ss);
    }
    else
    {
        writeByte(ss, 0);
    }

    bool hasDebug = !debugLocals.empty() || !debugUpvals.empty();

    if (hasDebug)
    {
        writeByte(ss, 1);

        writeVarInt(ss, uint32_t(debugLocals.size()));

        for (const DebugLocal& l : debugLocals)
        {
            writeVarInt(ss, l.name);
            writeVarInt(ss, l.startpc);
            writeVarInt(ss, l.endpc);
            writeByte(ss, l.reg);
        }

        writeVarInt(ss, uint32_t(debugUpvals.size()));

        for (const DebugUpval& l : debugUpvals)
        {
            writeVarInt(ss, l.name);
        }
    }
    else
    {
        writeByte(ss, 0);
    }
}

void BytecodeBuilder::writeLineInfo(std::string& ss) const
{
    LUAU_ASSERT(!lines.empty());

    // this function encodes lines inside each span as a 8-bit delta to span baseline
    // span is always a power of two; depending on the line info input, it may need to be as low as 1
    int span = 1 << 24;

    // first pass: determine span length
    for (size_t offset = 0; offset < lines.size(); offset += span)
    {
        size_t next = offset;

        int min = lines[offset];
        int max = lines[offset];

        for (; next < lines.size() && next < offset + span; ++next)
        {
            min = std::min(min, lines[next]);
            max = std::max(max, lines[next]);

            if (max - min > 255)
                break;
        }

        if (next < lines.size() && next - offset < size_t(span))
        {
            // since not all lines in the range fit in 8b delta, we need to shrink the span
            // next iteration will need to reprocess some lines again since span changed
            span = 1 << log2(int(next - offset));
        }
    }

    // second pass: compute span base
    int baselineOne = 0;
    std::vector<int> baselineScratch;
    int* baseline = &baselineOne;
    size_t baselineSize = (lines.size() - 1) / span + 1;

    if (baselineSize > 1)
    {
        // avoid heap allocation for single-element baseline which is most functions (<256 lines)
        baselineScratch.resize(baselineSize);
        baseline = baselineScratch.data();
    }

    for (size_t offset = 0; offset < lines.size(); offset += span)
    {
        size_t next = offset;

        int min = lines[offset];

        for (; next < lines.size() && next < offset + span; ++next)
            min = std::min(min, lines[next]);

        baseline[offset / span] = min;
    }

    // third pass: write resulting data
    int logspan = log2(span);

    writeByte(ss, uint8_t(logspan));

    uint8_t lastOffset = 0;

    for (size_t i = 0; i < lines.size(); ++i)
    {
        int delta = lines[i] - baseline[i >> logspan];
        LUAU_ASSERT(delta >= 0 && delta <= 255);

        writeByte(ss, uint8_t(delta) - lastOffset);
        lastOffset = uint8_t(delta);
    }

    int lastLine = 0;

    for (size_t i = 0; i < baselineSize; ++i)
    {
        writeInt(ss, baseline[i] - lastLine);
        lastLine = baseline[i];
    }
}

void BytecodeBuilder::writeStringTable(std::string& ss) const
{
    std::vector<StringRef> strings(stringTable.size());

    for (auto& p : stringTable)
    {
        LUAU_ASSERT(p.second > 0 && p.second <= strings.size());
        strings[p.second - 1] = p.first;
    }

    writeVarInt(ss, uint32_t(strings.size()));

    for (auto& s : strings)
    {
        writeVarInt(ss, uint32_t(s.length));
        ss.append(s.data, s.length);
    }
}

uint32_t BytecodeBuilder::getImportId(int32_t id0)
{
    LUAU_ASSERT(unsigned(id0) < 1024);

    return (1u << 30) | (id0 << 20);
}

uint32_t BytecodeBuilder::getImportId(int32_t id0, int32_t id1)
{
    LUAU_ASSERT(unsigned(id0 | id1) < 1024);

    return (2u << 30) | (id0 << 20) | (id1 << 10);
}

uint32_t BytecodeBuilder::getImportId(int32_t id0, int32_t id1, int32_t id2)
{
    LUAU_ASSERT(unsigned(id0 | id1 | id2) < 1024);

    return (3u << 30) | (id0 << 20) | (id1 << 10) | id2;
}

int BytecodeBuilder::decomposeImportId(uint32_t ids, int32_t& id0, int32_t& id1, int32_t& id2)
{
    int count = ids >> 30;
    id0 = count > 0 ? int(ids >> 20) & 1023 : -1;
    id1 = count > 1 ? int(ids >> 10) & 1023 : -1;
    id2 = count > 2 ? int(ids) & 1023 : -1;
    return count;
}

uint32_t BytecodeBuilder::getStringHash(StringRef key)
{
    // This hashing algorithm should match luaS_hash defined in VM/lstring.cpp for short inputs; we can't use that code directly to keep compiler and
    // VM independent in terms of compilation/linking. The resulting string hashes are embedded into bytecode binary and result in a better initial
    // guess for the field hashes which improves performance during initial code execution. We omit the long string processing here for simplicity, as
    // it doesn't really matter on long identifiers.
    const char* str = key.data;
    size_t len = key.length;

    unsigned int h = unsigned(len);

    // original Lua 5.1 hash for compatibility (exact match when len<32)
    for (size_t i = len; i > 0; --i)
        h ^= (h << 5) + (h >> 2) + (uint8_t)str[i - 1];

    return h;
}

void BytecodeBuilder::foldJumps()
{
    // if our function has long jumps, some processing below can make jump instructions not-jumps (e.g. JUMP->RETURN)
    // it's safer to skip this processing
    if (hasLongJumps)
        return;

    for (Jump& jump : jumps)
    {
        uint32_t jumpLabel = jump.source;

        uint32_t jumpInsn = insns[jumpLabel];

        // follow jump target through forward unconditional jumps
        // we only follow forward jumps to make sure the process terminates
        uint32_t targetLabel = jumpLabel + 1 + LUAU_INSN_D(jumpInsn);
        LUAU_ASSERT(targetLabel < insns.size());
        uint32_t targetInsn = insns[targetLabel];

        while (LUAU_INSN_OP(targetInsn) == LOP_JUMP && LUAU_INSN_D(targetInsn) >= 0)
        {
            targetLabel = targetLabel + 1 + LUAU_INSN_D(targetInsn);
            LUAU_ASSERT(targetLabel < insns.size());
            targetInsn = insns[targetLabel];
        }

        int offset = int(targetLabel) - int(jumpLabel) - 1;

        // for unconditional jumps to RETURN, we can replace JUMP with RETURN
        if (LUAU_INSN_OP(jumpInsn) == LOP_JUMP && LUAU_INSN_OP(targetInsn) == LOP_RETURN)
        {
            insns[jumpLabel] = targetInsn;
        }
        else if (int16_t(offset) == offset)
        {
            insns[jumpLabel] &= 0xffff;
            insns[jumpLabel] |= uint16_t(offset) << 16;
        }

        jump.target = targetLabel;
    }
}

void BytecodeBuilder::expandJumps()
{
    if (!hasLongJumps)
        return;

    // we have some jump instructions that couldn't be patched which means their offset didn't fit into 16 bits
    // our strategy for replacing instructions is as follows: instead of
    //   OP jumpoffset
    // we will synthesize a jump trampoline before our instruction (note that jump offsets are relative to next instruction):
    //   JUMP +1
    //   JUMPX jumpoffset
    //   OP -2
    // the idea is that during forward execution, we will jump over JUMPX into OP; if OP decides to jump, it will jump to JUMPX
    // JUMPX can carry a 24-bit jump offset

    // jump trampolines expand the code size, which can increase existing jump distances.
    // because of this, we may need to expand jumps that previously fit into 16-bit just fine.
    // the worst-case expansion is 3x, so to be conservative we will repatch all jumps that have an offset >= 32767/3
    const int kMaxJumpDistanceConservative = 32767 / 3;

    // we will need to process jumps in order
    std::sort(
        jumps.begin(),
        jumps.end(),
        [](const Jump& lhs, const Jump& rhs)
        {
            return lhs.source < rhs.source;
        }
    );

    // first, let's add jump thunks for every jump with a distance that's too big
    // we will create new instruction buffers, with remap table keeping track of the moves: remap[oldpc] = newpc
    std::vector<uint32_t> remap(insns.size());

    std::vector<uint32_t> newinsns;
    std::vector<int> newlines;

    LUAU_ASSERT(insns.size() == lines.size());
    newinsns.reserve(insns.size());
    newlines.reserve(insns.size());

    size_t currentJump = 0;
    size_t pendingTrampolines = 0;

    for (size_t i = 0; i < insns.size();)
    {
        uint8_t op = LUAU_INSN_OP(insns[i]);
        LUAU_ASSERT(op < LOP__COUNT);

        if (currentJump < jumps.size() && jumps[currentJump].source == i)
        {
            int offset = int(jumps[currentJump].target) - int(jumps[currentJump].source) - 1;

            if (abs(offset) > kMaxJumpDistanceConservative)
            {
                // insert jump trampoline as described above; we keep JUMPX offset uninitialized in this pass
                newinsns.push_back(LOP_JUMP | (1 << 16));
                newinsns.push_back(LOP_JUMPX);

                newlines.push_back(lines[i]);
                newlines.push_back(lines[i]);

                pendingTrampolines++;
            }

            currentJump++;
        }

        int oplen = getOpLength(LuauOpcode(op));

        // copy instruction and line info to the new stream
        for (int j = 0; j < oplen; ++j)
        {
            remap[i] = uint32_t(newinsns.size());

            newinsns.push_back(insns[i]);
            newlines.push_back(lines[i]);

            i++;
        }
    }

    LUAU_ASSERT(currentJump == jumps.size());
    LUAU_ASSERT(pendingTrampolines > 0);

    // now we need to recompute offsets for jump instructions - we could not do this in the first pass because the offsets are between *target*
    // instructions
    for (Jump& jump : jumps)
    {
        int offset = int(jump.target) - int(jump.source) - 1;
        int newoffset = int(remap[jump.target]) - int(remap[jump.source]) - 1;

        if (abs(offset) > kMaxJumpDistanceConservative)
        {
            // fix up jump trampoline
            uint32_t& insnt = newinsns[remap[jump.source] - 1];
            uint32_t& insnj = newinsns[remap[jump.source]];

            LUAU_ASSERT(LUAU_INSN_OP(insnt) == LOP_JUMPX);

            // patch JUMPX to JUMPX to target location; note that newoffset is the offset of the jump *relative to OP*, so we need to add 1 to make it
            // relative to JUMPX
            insnt &= 0xff;
            insnt |= uint32_t(newoffset + 1) << 8;

            // patch OP to OP -2
            insnj &= 0xffff;
            insnj |= uint16_t(-2) << 16;

            pendingTrampolines--;
        }
        else
        {
            uint32_t& insn = newinsns[remap[jump.source]];

            // make sure jump instruction had the correct offset before we started
            LUAU_ASSERT(LUAU_INSN_D(insn) == offset);

            // patch instruction with the new offset
            LUAU_ASSERT(int16_t(newoffset) == newoffset);

            insn &= 0xffff;
            insn |= uint16_t(newoffset) << 16;
        }
    }

    LUAU_ASSERT(pendingTrampolines == 0);

    // this was hard, but we're done.
    insns.swap(newinsns);
    lines.swap(newlines);

    for (DebugLocal& debugLocal : debugLocals)
    {
        // endpc is exclusive, to get the right remapping, we need to remap the location before the end
        if (debugLocal.startpc != debugLocal.endpc)
            debugLocal.endpc = remap[debugLocal.endpc - 1] + 1;
        else
            debugLocal.endpc = remap[debugLocal.endpc];

        debugLocal.startpc = remap[debugLocal.startpc];
    }

    for (TypedLocal& typedLocal : typedLocals)
    {
        // endpc is exclusive, to get the right remapping, we need to remap the location before the end
        if (typedLocal.startpc != typedLocal.endpc)
            typedLocal.endpc = remap[typedLocal.endpc - 1] + 1;
        else
            typedLocal.endpc = remap[typedLocal.endpc];

        typedLocal.startpc = remap[typedLocal.startpc];
    }
}

std::string BytecodeBuilder::getError(const std::string& message)
{
    // 0 acts as a special marker for error bytecode (it's equal to LBC_VERSION_TARGET for valid bytecode blobs)
    std::string result;
    result += char(0);
    result += message;

    return result;
}

uint8_t BytecodeBuilder::getVersion()
{
    if (FFlag::LuauCompileUdataDirect)
        return 9;

    // LBC_CONSTANT_INTEGER requires version 8
    if (FFlag::LuauIntegerType)
        return 8;

    // LBC_CONSTANT_TABLE_WITH_CONSTANTS requires version 7
    if (FFlag::LuauCompileDuptableConstantPack2)
        return 7;

    return LBC_VERSION_TARGET;
}

uint8_t BytecodeBuilder::getTypeEncodingVersion()
{
    return LBC_TYPE_VERSION_TARGET;
}

#ifdef LUAU_ASSERTENABLED
void BytecodeBuilder::validate() const
{
    validateInstructions();
    validateVariadic();
}

void BytecodeBuilder::validateInstructions() const
{
#define VREG(v) LUAU_ASSERT(unsigned(v) < func.maxstacksize)
#define VREGRANGE(v, count) LUAU_ASSERT(unsigned(v + (count < 0 ? 0 : count)) <= func.maxstacksize)
#define VUPVAL(v) LUAU_ASSERT(unsigned(v) < func.numupvalues)
#define VCONST(v, kind) LUAU_ASSERT(unsigned(v) < constants.size() && constants[v].type == Constant::Type_##kind)
#define VCONSTANY(v) LUAU_ASSERT(unsigned(v) < constants.size())
#define VJUMP(v) LUAU_ASSERT(size_t(i + 1 + v) < insns.size() && insnvalid[i + 1 + v])

    LUAU_ASSERT(currentFunction != ~0u);

    const Function& func = functions[currentFunction];

    // tag instruction offsets so that we can validate jumps
    std::vector<uint8_t> insnvalid(insns.size(), 0);

    for (size_t i = 0; i < insns.size();)
    {
        uint32_t insn = insns[i];
        LuauOpcode op = LuauOpcode(LUAU_INSN_OP(insn));

        insnvalid[i] = true;

        i += getOpLength(op);
        LUAU_ASSERT(i <= insns.size());
    }

    std::vector<uint8_t> openCaptures;

    // validate individual instructions
    for (size_t i = 0; i < insns.size();)
    {
        uint32_t insn = insns[i];
        LuauOpcode op = LuauOpcode(LUAU_INSN_OP(insn));

        switch (op)
        {
        case LOP_LOADNIL:
            VREG(LUAU_INSN_A(insn));
            break;

        case LOP_LOADB:
            VREG(LUAU_INSN_A(insn));
            LUAU_ASSERT(LUAU_INSN_B(insn) == 0 || LUAU_INSN_B(insn) == 1);
            VJUMP(LUAU_INSN_C(insn));
            break;

        case LOP_LOADN:
            VREG(LUAU_INSN_A(insn));
            break;

        case LOP_LOADK:
            VREG(LUAU_INSN_A(insn));
            VCONSTANY(LUAU_INSN_D(insn));
            break;

        case LOP_MOVE:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            break;

        case LOP_GETGLOBAL:
        case LOP_SETGLOBAL:
            VREG(LUAU_INSN_A(insn));
            VCONST(insns[i + 1], String);
            break;

        case LOP_GETUPVAL:
        case LOP_SETUPVAL:
            VREG(LUAU_INSN_A(insn));
            VUPVAL(LUAU_INSN_B(insn));
            break;

        case LOP_CLOSEUPVALS:
            VREG(LUAU_INSN_A(insn));
            while (openCaptures.size() && openCaptures.back() >= LUAU_INSN_A(insn))
                openCaptures.pop_back();
            break;

        case LOP_GETIMPORT:
        {
            VREG(LUAU_INSN_A(insn));
            VCONST(LUAU_INSN_D(insn), Import);
            uint32_t id = insns[i + 1];
            LUAU_ASSERT((id >> 30) != 0); // import chain with length 1-3
            for (unsigned int j = 0; j < (id >> 30); ++j)
                VCONST((id >> (20 - 10 * j)) & 1023, String);
        }
        break;

        case LOP_GETTABLE:
        case LOP_SETTABLE:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VREG(LUAU_INSN_C(insn));
            break;

        case LOP_GETTABLEKS:
        case LOP_SETTABLEKS:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VCONST(insns[i + 1], String);
            break;

        case LOP_GETTABLEN:
        case LOP_SETTABLEN:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            break;

        case LOP_NEWCLOSURE:
        {
            VREG(LUAU_INSN_A(insn));
            LUAU_ASSERT(unsigned(LUAU_INSN_D(insn)) < protos.size());
            LUAU_ASSERT(protos[LUAU_INSN_D(insn)] < functions.size());
            unsigned int numupvalues = functions[protos[LUAU_INSN_D(insn)]].numupvalues;

            for (unsigned int j = 0; j < numupvalues; ++j)
            {
                LUAU_ASSERT(i + 1 + j < insns.size());
                uint32_t cinsn = insns[i + 1 + j];
                LUAU_ASSERT(LUAU_INSN_OP(cinsn) == LOP_CAPTURE);
            }
        }
        break;

        case LOP_NAMECALL:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VCONST(insns[i + 1], String);
            LUAU_ASSERT(LUAU_INSN_OP(insns[i + 2]) == LOP_CALL);
            break;

        case LOP_CALL:
        {
            int nparams = LUAU_INSN_B(insn) - 1;
            int nresults = LUAU_INSN_C(insn) - 1;
            VREG(LUAU_INSN_A(insn));
            VREGRANGE(LUAU_INSN_A(insn) + 1, nparams); // 1..nparams
            VREGRANGE(LUAU_INSN_A(insn), nresults);    // 1..nresults
        }
        break;

        case LOP_RETURN:
        {
            int nresults = LUAU_INSN_B(insn) - 1;
            VREGRANGE(LUAU_INSN_A(insn), nresults); // 0..nresults-1
        }
        break;

        case LOP_JUMP:
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_JUMPIF:
        case LOP_JUMPIFNOT:
            VREG(LUAU_INSN_A(insn));
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_JUMPIFEQ:
        case LOP_JUMPIFLE:
        case LOP_JUMPIFLT:
        case LOP_JUMPIFNOTEQ:
        case LOP_JUMPIFNOTLE:
        case LOP_JUMPIFNOTLT:
            VREG(LUAU_INSN_A(insn));
            VREG(insns[i + 1]);
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_JUMPXEQKNIL:
        case LOP_JUMPXEQKB:
            VREG(LUAU_INSN_A(insn));
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_JUMPXEQKN:
            VREG(LUAU_INSN_A(insn));
            VCONST(insns[i + 1] & 0xffffff, Number);
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_JUMPXEQKS:
            VREG(LUAU_INSN_A(insn));
            VCONST(insns[i + 1] & 0xffffff, String);
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_ADD:
        case LOP_SUB:
        case LOP_MUL:
        case LOP_DIV:
        case LOP_IDIV:
        case LOP_MOD:
        case LOP_POW:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VREG(LUAU_INSN_C(insn));
            break;

        case LOP_ADDK:
        case LOP_SUBK:
        case LOP_MULK:
        case LOP_DIVK:
        case LOP_IDIVK:
        case LOP_MODK:
        case LOP_POWK:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VCONST(LUAU_INSN_C(insn), Number);
            break;

        case LOP_SUBRK:
        case LOP_DIVRK:
            VREG(LUAU_INSN_A(insn));
            VCONST(LUAU_INSN_B(insn), Number);
            VREG(LUAU_INSN_C(insn));
            break;

        case LOP_AND:
        case LOP_OR:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VREG(LUAU_INSN_C(insn));
            break;

        case LOP_ANDK:
        case LOP_ORK:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VCONSTANY(LUAU_INSN_C(insn));
            break;

        case LOP_CONCAT:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VREG(LUAU_INSN_C(insn));
            LUAU_ASSERT(LUAU_INSN_B(insn) <= LUAU_INSN_C(insn));
            break;

        case LOP_NOT:
        case LOP_MINUS:
        case LOP_LENGTH:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            break;

        case LOP_NEWTABLE:
            VREG(LUAU_INSN_A(insn));
            break;

        case LOP_DUPTABLE:
            VREG(LUAU_INSN_A(insn));
            VCONST(LUAU_INSN_D(insn), Table);
            break;

        case LOP_SETLIST:
        {
            int count = LUAU_INSN_C(insn) - 1;
            VREG(LUAU_INSN_A(insn));
            VREGRANGE(LUAU_INSN_B(insn), count);
        }
        break;

        case LOP_FORNPREP:
        case LOP_FORNLOOP:
            // for loop protocol: A, A+1, A+2 are used for iteration
            VREG(LUAU_INSN_A(insn) + 2);
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_FORGPREP:
            // forg loop protocol: A, A+1, A+2 are used for iteration protocol; A+3, ... are loop variables
            VREG(LUAU_INSN_A(insn) + 2 + 1);
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_FORGLOOP:
            // forg loop protocol: A, A+1, A+2 are used for iteration protocol; A+3, ... are loop variables
            VREG(LUAU_INSN_A(insn) + 2 + uint8_t(insns[i + 1]));
            VJUMP(LUAU_INSN_D(insn));
            LUAU_ASSERT(uint8_t(insns[i + 1]) >= 1);
            break;

        case LOP_FORGPREP_INEXT:
        case LOP_FORGPREP_NEXT:
            VREG(LUAU_INSN_A(insn) + 4); // forg loop protocol: A, A+1, A+2 are used for iteration protocol; A+3, A+4 are loop variables
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_GETVARARGS:
        {
            int nresults = LUAU_INSN_B(insn) - 1;
            VREGRANGE(LUAU_INSN_A(insn), nresults); // 0..nresults-1
        }
        break;

        case LOP_DUPCLOSURE:
        {
            VREG(LUAU_INSN_A(insn));
            VCONST(LUAU_INSN_D(insn), Closure);
            unsigned int proto = constants[LUAU_INSN_D(insn)].valueClosure;
            LUAU_ASSERT(proto < functions.size());
            unsigned int numupvalues = functions[proto].numupvalues;

            for (unsigned int j = 0; j < numupvalues; ++j)
            {
                LUAU_ASSERT(i + 1 + j < insns.size());
                uint32_t cinsn = insns[i + 1 + j];
                LUAU_ASSERT(LUAU_INSN_OP(cinsn) == LOP_CAPTURE);
                LUAU_ASSERT(LUAU_INSN_A(cinsn) == LCT_VAL || LUAU_INSN_A(cinsn) == LCT_UPVAL);
            }
        }
        break;

        case LOP_PREPVARARGS:
            LUAU_ASSERT(LUAU_INSN_A(insn) == func.numparams);
            LUAU_ASSERT(func.isvararg);
            break;

        case LOP_BREAK:
            break;

        case LOP_JUMPBACK:
            VJUMP(LUAU_INSN_D(insn));
            break;

        case LOP_LOADKX:
            VREG(LUAU_INSN_A(insn));
            VCONSTANY(insns[i + 1]);
            break;

        case LOP_JUMPX:
            VJUMP(LUAU_INSN_E(insn));
            break;

        case LOP_FASTCALL:
            VJUMP(LUAU_INSN_C(insn));
            LUAU_ASSERT(LUAU_INSN_OP(insns[i + 1 + LUAU_INSN_C(insn)]) == LOP_CALL);
            break;

        case LOP_FASTCALL1:
            VREG(LUAU_INSN_B(insn));
            VJUMP(LUAU_INSN_C(insn));
            LUAU_ASSERT(LUAU_INSN_OP(insns[i + 1 + LUAU_INSN_C(insn)]) == LOP_CALL);
            break;

        case LOP_FASTCALL2:
            VREG(LUAU_INSN_B(insn));
            VJUMP(LUAU_INSN_C(insn));
            LUAU_ASSERT(LUAU_INSN_OP(insns[i + 1 + LUAU_INSN_C(insn)]) == LOP_CALL);
            VREG(insns[i + 1]);
            break;

        case LOP_FASTCALL2K:
            VREG(LUAU_INSN_B(insn));
            VJUMP(LUAU_INSN_C(insn));
            LUAU_ASSERT(LUAU_INSN_OP(insns[i + 1 + LUAU_INSN_C(insn)]) == LOP_CALL);
            VCONSTANY(insns[i + 1]);
            break;

        case LOP_FASTCALL3:
            VREG(LUAU_INSN_B(insn));
            VJUMP(LUAU_INSN_C(insn));
            LUAU_ASSERT(LUAU_INSN_OP(insns[i + 1 + LUAU_INSN_C(insn)]) == LOP_CALL);
            VREG(insns[i + 1] & 0xff);
            VREG((insns[i + 1] >> 8) & 0xff);
            break;

        case LOP_COVERAGE:
            break;

        case LOP_CAPTURE:
            switch (LUAU_INSN_A(insn))
            {
            case LCT_VAL:
                VREG(LUAU_INSN_B(insn));
                break;

            case LCT_REF:
                VREG(LUAU_INSN_B(insn));
                openCaptures.push_back(LUAU_INSN_B(insn));
                break;

            case LCT_UPVAL:
                VUPVAL(LUAU_INSN_B(insn));
                break;

            default:
                LUAU_ASSERT(!"Unsupported capture type");
            }
            break;

        case LOP_GETUDATAKS:
        case LOP_SETUDATAKS:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VCONST(LUAU_INSN_AUX_KV16(insns[i + 1]), String);
            break;

        case LOP_NAMECALLUDATA:
            VREG(LUAU_INSN_A(insn));
            VREG(LUAU_INSN_B(insn));
            VCONST(LUAU_INSN_AUX_KV16(insns[i + 1]), String);
            LUAU_ASSERT(LUAU_INSN_OP(insns[i + 2]) == LOP_CALL);
            break;

        default:
            LUAU_ASSERT(!"Unsupported opcode");
        }

        i += getOpLength(op);
        LUAU_ASSERT(i <= insns.size());
    }

    // all CAPTURE REF instructions must have a CLOSEUPVALS instruction after them in the bytecode stream
    // this doesn't guarantee safety as it doesn't perform basic block based analysis, but if this fails
    // then the bytecode is definitely unsafe to run since the compiler won't generate backwards branches
    // except for loop edges
    LUAU_ASSERT(openCaptures.empty());

#undef VREG
#undef VREGEND
#undef VUPVAL
#undef VCONST
#undef VCONSTANY
#undef VJUMP
}

void BytecodeBuilder::validateVariadic() const
{
    // validate MULTRET sequences: instructions that produce a variadic sequence and consume one must come in pairs
    // we classify instructions into four groups: producers, consumers, neutral and others
    // any producer (an instruction that produces more than one value) must be followed by 0 or more neutral instructions
    // and a consumer (that consumes more than one value); these form a variadic sequence.
    // except for producer, no instruction in the variadic sequence may be a jump target.
    // from the execution perspective, producer adjusts L->top to point to one past the last result, neutral instructions
    // leave L->top unmodified, and consumer adjusts L->top back to the stack frame end.
    // consumers invalidate all values after L->top after they execute (which we currently don't validate)
    bool variadicSeq = false;

    std::vector<uint8_t> insntargets(insns.size(), 0);

    for (size_t i = 0; i < insns.size();)
    {
        uint32_t insn = insns[i];
        LuauOpcode op = LuauOpcode(LUAU_INSN_OP(insn));

        int target = getJumpTarget(insn, uint32_t(i));

        if (target >= 0 && !isFastCall(op))
        {
            LUAU_ASSERT(unsigned(target) < insns.size());

            insntargets[target] = true;
        }

        i += getOpLength(op);
        LUAU_ASSERT(i <= insns.size());
    }

    for (size_t i = 0; i < insns.size();)
    {
        uint32_t insn = insns[i];
        LuauOpcode op = LuauOpcode(LUAU_INSN_OP(insn));

        if (variadicSeq)
        {
            // no instruction inside the sequence, including the consumer, may be a jump target
            // this guarantees uninterrupted L->top adjustment flow
            LUAU_ASSERT(!insntargets[i]);
        }

        if (op == LOP_CALL)
        {
            // note: calls may end one variadic sequence and start a new one

            if (LUAU_INSN_B(insn) == 0)
            {
                // consumer instruction ends a variadic sequence
                LUAU_ASSERT(variadicSeq);
                variadicSeq = false;
            }
            else
            {
                // CALL is not a neutral instruction so it can't be present in a variadic sequence unless it's a consumer
                LUAU_ASSERT(!variadicSeq);
            }

            if (LUAU_INSN_C(insn) == 0)
            {
                // producer instruction starts a variadic sequence
                LUAU_ASSERT(!variadicSeq);
                variadicSeq = true;
            }
        }
        else if (op == LOP_GETVARARGS && LUAU_INSN_B(insn) == 0)
        {
            // producer instruction starts a variadic sequence
            LUAU_ASSERT(!variadicSeq);
            variadicSeq = true;
        }
        else if ((op == LOP_RETURN && LUAU_INSN_B(insn) == 0) || (op == LOP_SETLIST && LUAU_INSN_C(insn) == 0))
        {
            // consumer instruction ends a variadic sequence
            LUAU_ASSERT(variadicSeq);
            variadicSeq = false;
        }
        else if (op == LOP_FASTCALL)
        {
            int callTarget = int(i + LUAU_INSN_C(insn) + 1);
            LUAU_ASSERT(unsigned(callTarget) < insns.size() && LUAU_INSN_OP(insns[callTarget]) == LOP_CALL);

            if (LUAU_INSN_B(insns[callTarget]) == 0)
            {
                // consumer instruction ends a variadic sequence; however, we can't terminate it yet because future analysis of CALL will do it
                // during FASTCALL fallback, the instructions between this and CALL consumer are going to be executed before L->top so they must
                // be neutral; as such, we will defer termination of variadic sequence until CALL analysis
                LUAU_ASSERT(variadicSeq);
            }
            else
            {
                // FASTCALL is not a neutral instruction so it can't be present in a variadic sequence unless it's linked to CALL consumer
                LUAU_ASSERT(!variadicSeq);
            }

            // note: if FASTCALL is linked to a CALL producer, the instructions between FASTCALL and CALL are technically not part of an executed
            // variadic sequence since they are never executed if FASTCALL does anything, so it's okay to skip their validation until CALL
            // (we can't simply start a variadic sequence here because that would trigger assertions during linked CALL validation)
        }
        else if (op == LOP_CLOSEUPVALS || op == LOP_NAMECALL || op == LOP_GETIMPORT || op == LOP_MOVE || op == LOP_GETUPVAL || op == LOP_GETGLOBAL ||
                 op == LOP_GETTABLEKS || op == LOP_COVERAGE)
        {
            // instructions inside a variadic sequence must be neutral (can't change L->top)
            // while there are many neutral instructions like this, here we check that the instruction is one of the few
            // that we'd expect to exist in FASTCALL fallback sequences or between consecutive CALLs for encoding reasons
        }
        else
        {
            LUAU_ASSERT(!variadicSeq);
        }

        i += getOpLength(op);
        LUAU_ASSERT(i <= insns.size());
    }

    LUAU_ASSERT(!variadicSeq);
}
#endif

static bool printableStringConstant(const char* str, size_t len)
{
    for (size_t i = 0; i < len; ++i)
    {
        if (unsigned(str[i]) < ' ')
            return false;
    }

    return true;
}

void BytecodeBuilder::dumpConstant(std::string& result, int k) const
{
    LUAU_ASSERT(unsigned(k) < constants.size());
    const Constant& data = constants[k];

    switch (data.type)
    {
    case Constant::Type_Nil:
        formatAppend(result, "nil");
        break;
    case Constant::Type_Boolean:
        formatAppend(result, "%s", data.valueBoolean ? "true" : "false");
        break;
    case Constant::Type_Number:
        formatAppend(result, "%.17g", data.valueNumber);
        break;
    case Constant::Type_Integer:
        formatAppend(result, "%lld", (long long)(int64_t)data.valueInteger64);
        break;
    case Constant::Type_Vector:
        // 3-vectors is the most common configuration, so truncate to three components if possible
        if (data.valueVector[3] == 0.0)
            formatAppend(result, "%.9g, %.9g, %.9g", data.valueVector[0], data.valueVector[1], data.valueVector[2]);
        else
            formatAppend(result, "%.9g, %.9g, %.9g, %.9g", data.valueVector[0], data.valueVector[1], data.valueVector[2], data.valueVector[3]);
        break;
    case Constant::Type_String:
    {
        const StringRef& str = debugStrings[data.valueString - 1];

        if (printableStringConstant(str.data, str.length))
        {
            if (str.length < 32)
                formatAppend(result, "'%.*s'", int(str.length), str.data);
            else
                formatAppend(result, "'%.*s'...", 32, str.data);
        }
        else
        {
            formatAppend(result, "'");

            for (size_t i = 0; i < str.length && i < 32; ++i)
            {
                if (unsigned(str.data[i]) < ' ')
                    formatAppend(result, "\\x%02X", uint8_t(str.data[i]));
                else
                    formatAppend(result, "%c", str.data[i]);
            }

            if (str.length >= 32)
                formatAppend(result, "'...");
            else
                formatAppend(result, "'");
        }
        break;
    }
    case Constant::Type_Import:
    {
        int32_t id0 = -1, id1 = -1, id2 = -1;
        if (int count = decomposeImportId(data.valueImport, id0, id1, id2))
        {
            {
                const Constant& id = constants[id0];
                LUAU_ASSERT(id.type == Constant::Type_String && id.valueString <= debugStrings.size());

                const StringRef& str = debugStrings[id.valueString - 1];
                formatAppend(result, "%.*s", int(str.length), str.data);
            }

            if (count > 1)
            {
                const Constant& id = constants[id1];
                LUAU_ASSERT(id.type == Constant::Type_String && id.valueString <= debugStrings.size());

                const StringRef& str = debugStrings[id.valueString - 1];
                formatAppend(result, ".%.*s", int(str.length), str.data);
            }

            if (count > 2)
            {
                const Constant& id = constants[id2];
                LUAU_ASSERT(id.type == Constant::Type_String && id.valueString <= debugStrings.size());

                const StringRef& str = debugStrings[id.valueString - 1];
                formatAppend(result, ".%.*s", int(str.length), str.data);
            }
        }
        break;
    }
    case Constant::Type_Table:
        formatAppend(result, "{...}");
        break;
    case Constant::Type_Closure:
    {
        const Function& func = functions[data.valueClosure];

        if (!func.dumpname.empty())
            formatAppend(result, "'%s'", func.dumpname.c_str());
        break;
    }
    }
}

void BytecodeBuilder::dumpInstruction(const uint32_t* code, std::string& result, int targetLabel) const
{
    uint32_t insn = *code++;

    switch (LUAU_INSN_OP(insn))
    {
    case LOP_LOADNIL:
        formatAppend(result, "LOADNIL R%d\n", LUAU_INSN_A(insn));
        break;

    case LOP_LOADB:
        if (LUAU_INSN_C(insn))
            formatAppend(result, "LOADB R%d %d +%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        else
            formatAppend(result, "LOADB R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        break;

    case LOP_LOADN:
        formatAppend(result, "LOADN R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_D(insn));
        break;

    case LOP_LOADK:
        formatAppend(result, "LOADK R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_D(insn));
        dumpConstant(result, LUAU_INSN_D(insn));
        result.append("]\n");
        break;

    case LOP_MOVE:
        formatAppend(result, "MOVE R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        break;

    case LOP_GETGLOBAL:
        formatAppend(result, "GETGLOBAL R%d K%d [", LUAU_INSN_A(insn), *code);
        dumpConstant(result, *code);
        result.append("]\n");
        code++;
        break;

    case LOP_SETGLOBAL:
        formatAppend(result, "SETGLOBAL R%d K%d [", LUAU_INSN_A(insn), *code);
        dumpConstant(result, *code);
        result.append("]\n");
        code++;
        break;

    case LOP_GETUPVAL:
        formatAppend(result, "GETUPVAL R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        break;

    case LOP_SETUPVAL:
        formatAppend(result, "SETUPVAL R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        break;

    case LOP_CLOSEUPVALS:
        formatAppend(result, "CLOSEUPVALS R%d\n", LUAU_INSN_A(insn));
        break;

    case LOP_GETIMPORT:
        formatAppend(result, "GETIMPORT R%d %d [", LUAU_INSN_A(insn), LUAU_INSN_D(insn));
        dumpConstant(result, LUAU_INSN_D(insn));
        result.append("]\n");
        code++; // AUX
        break;

    case LOP_GETTABLE:
        formatAppend(result, "GETTABLE R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_SETTABLE:
        formatAppend(result, "SETTABLE R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_GETTABLEKS:
        formatAppend(result, "GETTABLEKS R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), *code);
        dumpConstant(result, *code);
        result.append("]\n");
        code++;
        break;

    case LOP_SETTABLEKS:
        formatAppend(result, "SETTABLEKS R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), *code);
        dumpConstant(result, *code);
        result.append("]\n");
        code++;
        break;

    case LOP_GETTABLEN:
        formatAppend(result, "GETTABLEN R%d R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn) + 1);
        break;

    case LOP_SETTABLEN:
        formatAppend(result, "SETTABLEN R%d R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn) + 1);
        break;

    case LOP_NEWCLOSURE:
        formatAppend(result, "NEWCLOSURE R%d P%d\n", LUAU_INSN_A(insn), LUAU_INSN_D(insn));
        break;

    case LOP_NAMECALL:
        formatAppend(result, "NAMECALL R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), *code);
        dumpConstant(result, *code);
        result.append("]\n");
        code++;
        break;

    case LOP_CALL:
        formatAppend(result, "CALL R%d %d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn) - 1, LUAU_INSN_C(insn) - 1);
        break;

    case LOP_RETURN:
        formatAppend(result, "RETURN R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn) - 1);
        break;

    case LOP_JUMP:
        formatAppend(result, "JUMP L%d\n", targetLabel);
        break;

    case LOP_JUMPIF:
        formatAppend(result, "JUMPIF R%d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_JUMPIFNOT:
        formatAppend(result, "JUMPIFNOT R%d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_JUMPIFEQ:
        formatAppend(result, "JUMPIFEQ R%d R%d L%d\n", LUAU_INSN_A(insn), *code++, targetLabel);
        break;

    case LOP_JUMPIFLE:
        formatAppend(result, "JUMPIFLE R%d R%d L%d\n", LUAU_INSN_A(insn), *code++, targetLabel);
        break;

    case LOP_JUMPIFLT:
        formatAppend(result, "JUMPIFLT R%d R%d L%d\n", LUAU_INSN_A(insn), *code++, targetLabel);
        break;

    case LOP_JUMPIFNOTEQ:
        formatAppend(result, "JUMPIFNOTEQ R%d R%d L%d\n", LUAU_INSN_A(insn), *code++, targetLabel);
        break;

    case LOP_JUMPIFNOTLE:
        formatAppend(result, "JUMPIFNOTLE R%d R%d L%d\n", LUAU_INSN_A(insn), *code++, targetLabel);
        break;

    case LOP_JUMPIFNOTLT:
        formatAppend(result, "JUMPIFNOTLT R%d R%d L%d\n", LUAU_INSN_A(insn), *code++, targetLabel);
        break;

    case LOP_ADD:
        formatAppend(result, "ADD R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_SUB:
        formatAppend(result, "SUB R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_MUL:
        formatAppend(result, "MUL R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_DIV:
        formatAppend(result, "DIV R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_IDIV:
        formatAppend(result, "IDIV R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_MOD:
        formatAppend(result, "MOD R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_POW:
        formatAppend(result, "POW R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_ADDK:
        formatAppend(result, "ADDK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_SUBK:
        formatAppend(result, "SUBK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_MULK:
        formatAppend(result, "MULK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_DIVK:
        formatAppend(result, "DIVK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_IDIVK:
        formatAppend(result, "IDIVK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_MODK:
        formatAppend(result, "MODK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_POWK:
        formatAppend(result, "POWK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_SUBRK:
        formatAppend(result, "SUBRK R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        dumpConstant(result, LUAU_INSN_B(insn));
        formatAppend(result, "] R%d\n", LUAU_INSN_C(insn));
        break;

    case LOP_DIVRK:
        formatAppend(result, "DIVRK R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        dumpConstant(result, LUAU_INSN_B(insn));
        formatAppend(result, "] R%d\n", LUAU_INSN_C(insn));
        break;

    case LOP_AND:
        formatAppend(result, "AND R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_OR:
        formatAppend(result, "OR R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_ANDK:
        formatAppend(result, "ANDK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_ORK:
        formatAppend(result, "ORK R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        dumpConstant(result, LUAU_INSN_C(insn));
        result.append("]\n");
        break;

    case LOP_CONCAT:
        formatAppend(result, "CONCAT R%d R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn));
        break;

    case LOP_NOT:
        formatAppend(result, "NOT R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        break;

    case LOP_MINUS:
        formatAppend(result, "MINUS R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        break;

    case LOP_LENGTH:
        formatAppend(result, "LENGTH R%d R%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn));
        break;

    case LOP_NEWTABLE:
        formatAppend(result, "NEWTABLE R%d %d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn) == 0 ? 0 : 1 << (LUAU_INSN_B(insn) - 1), *code++);
        break;

    case LOP_DUPTABLE:
        formatAppend(result, "DUPTABLE R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_D(insn));
        break;

    case LOP_SETLIST:
        formatAppend(result, "SETLIST R%d R%d %d [%d]\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_C(insn) - 1, *code++);
        break;

    case LOP_FORNPREP:
        formatAppend(result, "FORNPREP R%d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_FORNLOOP:
        formatAppend(result, "FORNLOOP R%d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_FORGPREP:
        formatAppend(result, "FORGPREP R%d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_FORGLOOP:
        formatAppend(result, "FORGLOOP R%d L%d %d%s\n", LUAU_INSN_A(insn), targetLabel, uint8_t(*code), int(*code) < 0 ? " [inext]" : "");
        code++;
        break;

    case LOP_FORGPREP_INEXT:
        formatAppend(result, "FORGPREP_INEXT R%d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_FORGPREP_NEXT:
        formatAppend(result, "FORGPREP_NEXT R%d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_GETVARARGS:
        formatAppend(result, "GETVARARGS R%d %d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn) - 1);
        break;

    case LOP_DUPCLOSURE:
        formatAppend(result, "DUPCLOSURE R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_D(insn));
        dumpConstant(result, LUAU_INSN_D(insn));
        result.append("]\n");
        break;

    case LOP_BREAK:
        formatAppend(result, "BREAK\n");
        break;

    case LOP_JUMPBACK:
        formatAppend(result, "JUMPBACK L%d\n", targetLabel);
        break;

    case LOP_LOADKX:
        formatAppend(result, "LOADKX R%d K%d [", LUAU_INSN_A(insn), *code);
        dumpConstant(result, *code);
        result.append("]\n");
        code++;
        break;

    case LOP_JUMPX:
        formatAppend(result, "JUMPX L%d\n", targetLabel);
        break;

    case LOP_FASTCALL:
        formatAppend(result, "FASTCALL %d L%d\n", LUAU_INSN_A(insn), targetLabel);
        break;

    case LOP_FASTCALL1:
        formatAppend(result, "FASTCALL1 %d R%d L%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), targetLabel);
        break;

    case LOP_FASTCALL2:
        formatAppend(result, "FASTCALL2 %d R%d R%d L%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), *code, targetLabel);
        code++;
        break;

    case LOP_FASTCALL2K:
        formatAppend(result, "FASTCALL2K %d R%d K%d L%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), *code, targetLabel);
        dumpConstant(result, *code);
        result.append("]\n");
        code++;
        break;

    case LOP_FASTCALL3:
        formatAppend(result, "FASTCALL3 %d R%d R%d R%d L%d\n", LUAU_INSN_A(insn), LUAU_INSN_B(insn), *code & 0xff, (*code >> 8) & 0xff, targetLabel);
        code++;
        break;

    case LOP_COVERAGE:
        formatAppend(result, "COVERAGE\n");
        break;

    case LOP_CAPTURE:
        formatAppend(
            result,
            "CAPTURE %s %c%d\n",
            LUAU_INSN_A(insn) == LCT_UPVAL ? "UPVAL"
            : LUAU_INSN_A(insn) == LCT_REF ? "REF"
            : LUAU_INSN_A(insn) == LCT_VAL ? "VAL"
                                           : "",
            LUAU_INSN_A(insn) == LCT_UPVAL ? 'U' : 'R',
            LUAU_INSN_B(insn)
        );
        break;

    case LOP_JUMPXEQKNIL:
        formatAppend(result, "JUMPXEQKNIL R%d L%d%s\n", LUAU_INSN_A(insn), targetLabel, *code >> 31 ? " NOT" : "");
        code++;
        break;

    case LOP_JUMPXEQKB:
        formatAppend(result, "JUMPXEQKB R%d %d L%d%s\n", LUAU_INSN_A(insn), *code & 1, targetLabel, *code >> 31 ? " NOT" : "");
        code++;
        break;

    case LOP_JUMPXEQKN:
        formatAppend(result, "JUMPXEQKN R%d K%d L%d%s [", LUAU_INSN_A(insn), *code & 0xffffff, targetLabel, *code >> 31 ? " NOT" : "");
        dumpConstant(result, *code & 0xffffff);
        result.append("]\n");
        code++;
        break;

    case LOP_JUMPXEQKS:
        formatAppend(result, "JUMPXEQKS R%d K%d L%d%s [", LUAU_INSN_A(insn), *code & 0xffffff, targetLabel, *code >> 31 ? " NOT" : "");
        dumpConstant(result, *code & 0xffffff);
        result.append("]\n");
        code++;
        break;

    case LOP_GETUDATAKS:
        formatAppend(result, "GETUDATAKS R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_AUX_KV16(*code));
        dumpConstant(result, LUAU_INSN_AUX_KV16(*code));
        result.append("]\n");
        code++;
        break;

    case LOP_SETUDATAKS:
        formatAppend(result, "SETUDATAKS R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_AUX_KV16(*code));
        dumpConstant(result, LUAU_INSN_AUX_KV16(*code));
        result.append("]\n");
        code++;
        break;

    case LOP_NAMECALLUDATA:
        formatAppend(result, "NAMECALLUDATA R%d R%d K%d [", LUAU_INSN_A(insn), LUAU_INSN_B(insn), LUAU_INSN_AUX_KV16(*code));
        dumpConstant(result, LUAU_INSN_AUX_KV16(*code));
        result.append("]\n");
        code++;
        break;

    default:
        LUAU_ASSERT(!"Unsupported opcode");
    }
}

static const char* getBaseTypeString(uint8_t type)
{
    uint8_t tag = type & ~LBC_TYPE_OPTIONAL_BIT;
    switch (tag)
    {
    case LBC_TYPE_NIL:
        return "nil";
    case LBC_TYPE_BOOLEAN:
        return "boolean";
    case LBC_TYPE_NUMBER:
        return "number";
    case LBC_TYPE_INTEGER:
        return "integer";
    case LBC_TYPE_STRING:
        return "string";
    case LBC_TYPE_TABLE:
        return "table";
    case LBC_TYPE_FUNCTION:
        return "function";
    case LBC_TYPE_THREAD:
        return "thread";
    case LBC_TYPE_USERDATA:
        return "userdata";
    case LBC_TYPE_VECTOR:
        return "vector";
    case LBC_TYPE_BUFFER:
        return "buffer";
    case LBC_TYPE_ANY:
        return "any";
    }

    LUAU_ASSERT(!"Unhandled type in getBaseTypeString");
    return nullptr;
}

std::string BytecodeBuilder::dumpCurrentFunction(std::vector<int>& dumpinstoffs) const
{
    if ((dumpFlags & (Dump_Code | Dump_Constants)) == 0)
        return std::string();

    int lastLine = -1;
    size_t nextRemark = 0;

    std::string result;

    if (dumpFlags & Dump_Locals)
    {
        for (size_t i = 0; i < debugLocals.size(); ++i)
        {
            const DebugLocal& l = debugLocals[i];

            if (l.startpc == l.endpc)
            {
                LUAU_ASSERT(l.startpc < lines.size());

                // it would be nice to emit name as well but it requires reverse lookup through stringtable
                formatAppend(result, "local %d: reg %d, start pc %d line %d, no live range\n", int(i), l.reg, l.startpc, lines[l.startpc]);
            }
            else
            {
                LUAU_ASSERT(l.startpc < l.endpc);
                LUAU_ASSERT(l.startpc < lines.size());
                LUAU_ASSERT(l.endpc <= lines.size()); // endpc is exclusive in the debug info, but it's more intuitive to print inclusive data

                // it would be nice to emit name as well but it requires reverse lookup through stringtable
                formatAppend(
                    result,
                    "local %d: reg %d, start pc %d line %d, end pc %d line %d\n",
                    int(i),
                    l.reg,
                    l.startpc,
                    lines[l.startpc],
                    l.endpc - 1,
                    lines[l.endpc - 1]
                );
            }
        }
    }

    if (dumpFlags & Dump_Types)
    {
        const std::string& typeinfo = functions.back().typeinfo;

        // Arguments start from third byte in function typeinfo string
        for (uint8_t i = 2; i < typeinfo.size(); ++i)
        {
            uint8_t et = typeinfo[i];

            const char* userdata = tryGetUserdataTypeName(LuauBytecodeType(et));
            const char* name = userdata ? userdata : getBaseTypeString(et);
            const char* optional = (et & LBC_TYPE_OPTIONAL_BIT) ? "?" : "";

            formatAppend(result, "R%d: %s%s [argument]\n", i - 2, name, optional);
        }

        for (size_t i = 0; i < typedUpvals.size(); ++i)
        {
            const TypedUpval& l = typedUpvals[i];

            const char* userdata = tryGetUserdataTypeName(l.type);
            const char* name = userdata ? userdata : getBaseTypeString(l.type);
            const char* optional = (l.type & LBC_TYPE_OPTIONAL_BIT) ? "?" : "";

            formatAppend(result, "U%d: %s%s\n", int(i), name, optional);
        }

        for (size_t i = 0; i < typedLocals.size(); ++i)
        {
            const TypedLocal& l = typedLocals[i];

            const char* userdata = tryGetUserdataTypeName(l.type);
            const char* name = userdata ? userdata : getBaseTypeString(l.type);
            const char* optional = (l.type & LBC_TYPE_OPTIONAL_BIT) ? "?" : "";

            formatAppend(result, "R%d: %s%s from %d to %d\n", l.reg, name, optional, l.startpc, l.endpc);
        }
    }

    if (dumpFlags & Dump_Constants)
    {
        for (size_t i = 0; i < constants.size(); ++i)
        {
            formatAppend(result, "K%d: ", int(i));
            dumpConstant(result, int(i));
            formatAppend(result, "\n");
        }
    }

    if (dumpFlags & Dump_Code)
    {
        std::vector<int> labels(insns.size(), -1);

        // annotate valid jump targets with 0
        for (size_t i = 0; i < insns.size();)
        {
            int target = getJumpTarget(insns[i], uint32_t(i));

            if (target >= 0)
            {
                LUAU_ASSERT(size_t(target) < insns.size());
                labels[target] = 0;
            }

            i += getOpLength(LuauOpcode(LUAU_INSN_OP(insns[i])));
            LUAU_ASSERT(i <= insns.size());
        }

        int nextLabel = 0;

        // compute label ids (sequential integers for all jump targets)
        for (size_t i = 0; i < labels.size(); ++i)
            if (labels[i] == 0)
                labels[i] = nextLabel++;

        dumpinstoffs.resize(insns.size() + 1, -1);

        for (size_t i = 0; i < insns.size();)
        {
            const uint32_t* code = &insns[i];
            uint8_t op = LUAU_INSN_OP(*code);

            dumpinstoffs[i] = int(result.size());

            if (op == LOP_PREPVARARGS)
            {
                // Don't emit function header in bytecode - it's used for call dispatching and doesn't contain "interesting" information
                i++;
                continue;
            }

            if (dumpFlags & Dump_Remarks)
            {
                while (nextRemark < debugRemarks.size() && debugRemarks[nextRemark].first == i)
                {
                    formatAppend(result, "REMARK %s\n", debugRemarkBuffer.c_str() + debugRemarks[nextRemark].second);
                    nextRemark++;
                }
            }

            if (dumpFlags & Dump_Source)
            {
                int line = lines[i];

                if (line > 0 && line != lastLine)
                {
                    LUAU_ASSERT(size_t(line - 1) < dumpSource.size());
                    formatAppend(result, "%5d: %s\n", line, dumpSource[line - 1].c_str());
                    lastLine = line;
                }
            }

            if (dumpFlags & Dump_Lines)
                formatAppend(result, "%d: ", lines[i]);

            if (labels[i] != -1)
                formatAppend(result, "L%d: ", labels[i]);

            int target = getJumpTarget(*code, uint32_t(i));

            dumpInstruction(code, result, target >= 0 ? labels[target] : -1);

            i += getOpLength(LuauOpcode(op));
            LUAU_ASSERT(i <= insns.size());
        }

        dumpinstoffs[insns.size()] = int(result.size());
    }

    return result;
}

void BytecodeBuilder::setDumpSource(const std::string& source)
{
    dumpSource.clear();

    size_t pos = 0;

    while (pos != std::string::npos)
    {
        size_t next = source.find('\n', pos);

        if (next == std::string::npos)
        {
            dumpSource.push_back(source.substr(pos));
            pos = next;
        }
        else
        {
            dumpSource.push_back(source.substr(pos, next - pos));
            pos = next + 1;
        }

        if (!dumpSource.back().empty() && dumpSource.back().back() == '\r')
            dumpSource.back().pop_back();
    }
}

std::string BytecodeBuilder::dumpFunction(uint32_t id) const
{
    LUAU_ASSERT(id < functions.size());

    return functions[id].dump;
}

std::string BytecodeBuilder::dumpEverything() const
{
    std::string result;

    for (size_t i = 0; i < functions.size(); ++i)
    {
        std::string debugname = functions[i].dumpname.empty() ? "??" : functions[i].dumpname;

        formatAppend(result, "Function %d (%s):\n", int(i), debugname.c_str());

        result += functions[i].dump;
        result += "\n";
    }

    return result;
}

std::string BytecodeBuilder::dumpSourceRemarks() const
{
    std::string result;

    size_t nextRemark = 0;

    std::vector<std::pair<int, std::string>> remarks = dumpRemarks;
    std::sort(remarks.begin(), remarks.end());

    for (size_t i = 0; i < dumpSource.size(); ++i)
    {
        const std::string& line = dumpSource[i];

        size_t indent = 0;
        while (indent < line.length() && (line[indent] == ' ' || line[indent] == '\t'))
            indent++;

        while (nextRemark < remarks.size() && remarks[nextRemark].first == int(i + 1))
        {
            formatAppend(result, "%.*s-- remark: %s\n", int(indent), line.c_str(), remarks[nextRemark].second.c_str());
            nextRemark++;

            // skip duplicate remarks (due to inlining/unrolling)
            while (nextRemark < remarks.size() && remarks[nextRemark] == remarks[nextRemark - 1])
                nextRemark++;
        }

        result += line;

        if (i + 1 < dumpSource.size())
            result += '\n';
    }

    return result;
}

std::string BytecodeBuilder::dumpTypeInfo() const
{
    std::string result;

    for (size_t i = 0; i < functions.size(); ++i)
    {
        const std::string& typeinfo = functions[i].typeinfo;
        if (typeinfo.empty())
            continue;

        uint8_t encodedType = typeinfo[0];

        LUAU_ASSERT(encodedType == LBC_TYPE_FUNCTION);

        formatAppend(result, "%zu: function(", i);

        LUAU_ASSERT(typeinfo.size() >= 2);

        uint8_t numparams = typeinfo[1];

        LUAU_ASSERT(size_t(1 + numparams - 1) < typeinfo.size());

        for (uint8_t i = 0; i < numparams; ++i)
        {
            uint8_t et = typeinfo[2 + i];
            const char* optional = (et & LBC_TYPE_OPTIONAL_BIT) ? "?" : "";
            formatAppend(result, "%s%s", getBaseTypeString(et), optional);

            if (i + 1 != numparams)
                formatAppend(result, ", ");
        }

        formatAppend(result, ")\n");
    }

    return result;
}

void BytecodeBuilder::annotateInstruction(std::string& result, uint32_t fid, uint32_t instpos) const
{
    if ((dumpFlags & Dump_Code) == 0)
        return;

    LUAU_ASSERT(fid < functions.size());

    const Function& function = functions[fid];
    const std::string& dump = function.dump;
    const std::vector<int>& dumpinstoffs = function.dumpinstoffs;

    uint32_t next = instpos + 1;

    LUAU_ASSERT(next < dumpinstoffs.size());

    // Skip locations of multi-dword instructions
    while (next < dumpinstoffs.size() && dumpinstoffs[next] == -1)
        next++;

    formatAppend(result, "%.*s", dumpinstoffs[next] - dumpinstoffs[instpos], dump.data() + dumpinstoffs[instpos]);
}

} // namespace Luau
