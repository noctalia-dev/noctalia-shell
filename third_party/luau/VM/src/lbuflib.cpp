// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "lualib.h"

#include "lcommon.h"
#include "lbuffer.h"

#if defined(LUAU_BIG_ENDIAN)
#include <endian.h>
#endif

LUAU_FASTFLAG(LuauIntegerType)
LUAU_FASTFLAG(LuauIntegerLibrary)

#include <string.h>

// while C API returns 'size_t' for binary compatibility in case of future extensions,
// in the current implementation, length and offset are limited to 31 bits
// because offset is limited to an integer, a single 64bit comparison can be used and will not overflow
#define isoutofbounds(offset, len, accessize) (uint64_t(unsigned(offset)) + (accessize) > uint64_t(len))

static_assert(MAX_BUFFER_SIZE <= INT_MAX, "current implementation can't handle a larger limit");

#if defined(LUAU_BIG_ENDIAN)
template<typename T>
inline T buffer_swapbe(T v)
{
    if (sizeof(T) == 8)
        return htole64(v);
    else if (sizeof(T) == 4)
        return htole32(v);
    else if (sizeof(T) == 2)
        return htole16(v);
    else
        return v;
}
#endif

static int buffer_create(lua_State* L)
{
    int size = luaL_checkinteger(L, 1);

    luaL_argcheck(L, size >= 0, 1, "size");

    lua_newbuffer(L, size);
    return 1;
}

static int buffer_fromstring(lua_State* L)
{
    size_t len = 0;
    const char* val = luaL_checklstring(L, 1, &len);

    void* data = lua_newbuffer(L, len);
    memcpy(data, val, len);
    return 1;
}

static int buffer_tostring(lua_State* L)
{
    size_t len = 0;
    void* data = luaL_checkbuffer(L, 1, &len);

    lua_pushlstring(L, (char*)data, len);
    return 1;
}

template<typename T>
static int buffer_readinteger(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);

    if (isoutofbounds(offset, len, sizeof(T)))
        luaL_error(L, "buffer access out of bounds");

    T val;
    memcpy(&val, (char*)buf + offset, sizeof(T));

#if defined(LUAU_BIG_ENDIAN)
    val = buffer_swapbe(val);
#endif

    lua_pushnumber(L, double(val));
    return 1;
}

template<typename T>
static int buffer_writeinteger(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);
    int value = luaL_checkunsigned(L, 3);

    if (isoutofbounds(offset, len, sizeof(T)))
        luaL_error(L, "buffer access out of bounds");

    T val = T(value);

#if defined(LUAU_BIG_ENDIAN)
    val = buffer_swapbe(val);
#endif

    memcpy((char*)buf + offset, &val, sizeof(T));
    return 0;
}

static int buffer_readlong(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);

    if (isoutofbounds(offset, len, sizeof(uint64_t)))
        luaL_error(L, "buffer access out of bounds");

    int64_t val;
    memcpy(&val, (char*)buf + offset, sizeof(int64_t));

#if defined(LUAU_BIG_ENDIAN)
    val = buffer_swapbe(val);
#endif

    lua_pushinteger64(L, val);
    return 1;
}

static int buffer_writelong(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);
    int64_t value = luaL_checkinteger64(L, 3);

    if (isoutofbounds(offset, len, sizeof(int64_t)))
        luaL_error(L, "buffer access out of bounds");

#if defined(LUAU_BIG_ENDIAN)
    value = buffer_swapbe(value);
#endif

    memcpy((char*)buf + offset, &value, sizeof(int64_t));
    return 0;
}

template<typename T, typename StorageType>
static int buffer_readfp(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);

    if (isoutofbounds(offset, len, sizeof(T)))
        luaL_error(L, "buffer access out of bounds");

    T val;

#if defined(LUAU_BIG_ENDIAN)
    static_assert(sizeof(T) == sizeof(StorageType), "type size must match to reinterpret data");
    StorageType tmp;
    memcpy(&tmp, (char*)buf + offset, sizeof(tmp));
    tmp = buffer_swapbe(tmp);

    memcpy(&val, &tmp, sizeof(tmp));
#else
    memcpy(&val, (char*)buf + offset, sizeof(T));
#endif

    lua_pushnumber(L, double(val));
    return 1;
}

template<typename T, typename StorageType>
static int buffer_writefp(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);
    double value = luaL_checknumber(L, 3);

    if (isoutofbounds(offset, len, sizeof(T)))
        luaL_error(L, "buffer access out of bounds");

    T val = T(value);

#if defined(LUAU_BIG_ENDIAN)
    static_assert(sizeof(T) == sizeof(StorageType), "type size must match to reinterpret data");
    StorageType tmp;
    memcpy(&tmp, &val, sizeof(tmp));
    tmp = buffer_swapbe(tmp);

    memcpy((char*)buf + offset, &tmp, sizeof(tmp));
#else
    memcpy((char*)buf + offset, &val, sizeof(T));
#endif

    return 0;
}

static int buffer_readstring(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);
    int size = luaL_checkinteger(L, 3);

    luaL_argcheck(L, size >= 0, 3, "size");

    if (isoutofbounds(offset, len, unsigned(size)))
        luaL_error(L, "buffer access out of bounds");

    lua_pushlstring(L, (char*)buf + offset, size);
    return 1;
}

static int buffer_writestring(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);
    size_t size = 0;
    const char* val = luaL_checklstring(L, 3, &size);
    int count = luaL_optinteger(L, 4, int(size));

    luaL_argcheck(L, count >= 0, 4, "count");

    if (size_t(count) > size)
        luaL_error(L, "string length overflow");

    // string size can't exceed INT_MAX at this point
    if (isoutofbounds(offset, len, unsigned(count)))
        luaL_error(L, "buffer access out of bounds");

    memcpy((char*)buf + offset, val, count);
    return 0;
}

static int buffer_len(lua_State* L)
{
    size_t len = 0;
    luaL_checkbuffer(L, 1, &len);

    lua_pushnumber(L, double(unsigned(len)));
    return 1;
}

static int buffer_copy(lua_State* L)
{
    size_t tlen = 0;
    void* tbuf = luaL_checkbuffer(L, 1, &tlen);
    int toffset = luaL_checkinteger(L, 2);

    size_t slen = 0;
    void* sbuf = luaL_checkbuffer(L, 3, &slen);
    int soffset = luaL_optinteger(L, 4, 0);

    int size = luaL_optinteger(L, 5, int(slen) - soffset);

    if (size < 0)
        luaL_error(L, "buffer access out of bounds");

    if (isoutofbounds(soffset, slen, unsigned(size)))
        luaL_error(L, "buffer access out of bounds");

    if (isoutofbounds(toffset, tlen, unsigned(size)))
        luaL_error(L, "buffer access out of bounds");

    memmove((char*)tbuf + toffset, (char*)sbuf + soffset, size);
    return 0;
}

static int buffer_fill(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int offset = luaL_checkinteger(L, 2);
    unsigned value = luaL_checkunsigned(L, 3);
    int size = luaL_optinteger(L, 4, int(len) - offset);

    if (size < 0)
        luaL_error(L, "buffer access out of bounds");

    if (isoutofbounds(offset, len, unsigned(size)))
        luaL_error(L, "buffer access out of bounds");

    memset((char*)buf + offset, value & 0xff, size);
    return 0;
}

static int buffer_readbits(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int64_t bitoffset = (int64_t)luaL_checknumber(L, 2);
    int bitcount = luaL_checkinteger(L, 3);

    if (bitoffset < 0)
        luaL_error(L, "buffer access out of bounds");

    if (unsigned(bitcount) > 32)
        luaL_error(L, "bit count is out of range of [0; 32]");

    if (uint64_t(bitoffset + bitcount) > uint64_t(len) * 8)
        luaL_error(L, "buffer access out of bounds");

    unsigned startbyte = unsigned(bitoffset / 8);
    unsigned endbyte = unsigned((bitoffset + bitcount + 7) / 8);

    uint64_t data = 0;

#if defined(LUAU_BIG_ENDIAN)
    for (int i = int(endbyte) - 1; i >= int(startbyte); i--)
        data = (data << 8) + uint8_t(((char*)buf)[i]);
#else
    memcpy(&data, (char*)buf + startbyte, endbyte - startbyte);
#endif

    uint64_t subbyteoffset = bitoffset & 0x7;
    uint64_t mask = (1ull << bitcount) - 1;

    lua_pushunsigned(L, unsigned((data >> subbyteoffset) & mask));
    return 1;
}

static int buffer_writebits(lua_State* L)
{
    size_t len = 0;
    void* buf = luaL_checkbuffer(L, 1, &len);
    int64_t bitoffset = (int64_t)luaL_checknumber(L, 2);
    int bitcount = luaL_checkinteger(L, 3);
    unsigned value = luaL_checkunsigned(L, 4);

    if (bitoffset < 0)
        luaL_error(L, "buffer access out of bounds");

    if (unsigned(bitcount) > 32)
        luaL_error(L, "bit count is out of range of [0; 32]");

    if (uint64_t(bitoffset + bitcount) > uint64_t(len) * 8)
        luaL_error(L, "buffer access out of bounds");

    unsigned startbyte = unsigned(bitoffset / 8);
    unsigned endbyte = unsigned((bitoffset + bitcount + 7) / 8);

    uint64_t data = 0;

#if defined(LUAU_BIG_ENDIAN)
    for (int i = int(endbyte) - 1; i >= int(startbyte); i--)
        data = data * 256 + uint8_t(((char*)buf)[i]);
#else
    memcpy(&data, (char*)buf + startbyte, endbyte - startbyte);
#endif

    uint64_t subbyteoffset = bitoffset & 0x7;
    uint64_t mask = ((1ull << bitcount) - 1) << subbyteoffset;

    data = (data & ~mask) | ((uint64_t(value) << subbyteoffset) & mask);

#if defined(LUAU_BIG_ENDIAN)
    for (int i = int(startbyte); i < int(endbyte); i++)
    {
        ((char*)buf)[i] = data & 0xff;
        data >>= 8;
    }
#else
    memcpy((char*)buf + startbyte, &data, endbyte - startbyte);
#endif
    return 0;
}

static const luaL_Reg bufferlib[] = {
    {"create", buffer_create},
    {"fromstring", buffer_fromstring},
    {"tostring", buffer_tostring},
    {"readi8", buffer_readinteger<int8_t>},
    {"readu8", buffer_readinteger<uint8_t>},
    {"readi16", buffer_readinteger<int16_t>},
    {"readu16", buffer_readinteger<uint16_t>},
    {"readi32", buffer_readinteger<int32_t>},
    {"readu32", buffer_readinteger<uint32_t>},
    {"readf32", buffer_readfp<float, uint32_t>},
    {"readf64", buffer_readfp<double, uint64_t>},
    {"writei8", buffer_writeinteger<int8_t>},
    {"writeu8", buffer_writeinteger<uint8_t>},
    {"writei16", buffer_writeinteger<int16_t>},
    {"writeu16", buffer_writeinteger<uint16_t>},
    {"writei32", buffer_writeinteger<int32_t>},
    {"writeu32", buffer_writeinteger<uint32_t>},
    {"writef32", buffer_writefp<float, uint32_t>},
    {"writef64", buffer_writefp<double, uint64_t>},
    {"readstring", buffer_readstring},
    {"writestring", buffer_writestring},
    {"len", buffer_len},
    {"copy", buffer_copy},
    {"fill", buffer_fill},
    {"readbits", buffer_readbits},
    {"writebits", buffer_writebits},
    {"readinteger", buffer_readlong},
    {"writeinteger", buffer_writelong},
    {NULL, NULL},
};

static const luaL_Reg bufferlib_NOINTEGER[] = {
    {"create", buffer_create},
    {"fromstring", buffer_fromstring},
    {"tostring", buffer_tostring},
    {"readi8", buffer_readinteger<int8_t>},
    {"readu8", buffer_readinteger<uint8_t>},
    {"readi16", buffer_readinteger<int16_t>},
    {"readu16", buffer_readinteger<uint16_t>},
    {"readi32", buffer_readinteger<int32_t>},
    {"readu32", buffer_readinteger<uint32_t>},
    {"readf32", buffer_readfp<float, uint32_t>},
    {"readf64", buffer_readfp<double, uint64_t>},
    {"writei8", buffer_writeinteger<int8_t>},
    {"writeu8", buffer_writeinteger<uint8_t>},
    {"writei16", buffer_writeinteger<int16_t>},
    {"writeu16", buffer_writeinteger<uint16_t>},
    {"writei32", buffer_writeinteger<int32_t>},
    {"writeu32", buffer_writeinteger<uint32_t>},
    {"writef32", buffer_writefp<float, uint32_t>},
    {"writef64", buffer_writefp<double, uint64_t>},
    {"readstring", buffer_readstring},
    {"writestring", buffer_writestring},
    {"len", buffer_len},
    {"copy", buffer_copy},
    {"fill", buffer_fill},
    {"readbits", buffer_readbits},
    {"writebits", buffer_writebits},
    {NULL, NULL},
};

int luaopen_buffer(lua_State* L)
{
    if (FFlag::LuauIntegerType && FFlag::LuauIntegerLibrary)
        luaL_register(L, LUA_BUFFERLIBNAME, bufferlib);
    else
        luaL_register(L, LUA_BUFFERLIBNAME, bufferlib_NOINTEGER);

    return 1;
}
