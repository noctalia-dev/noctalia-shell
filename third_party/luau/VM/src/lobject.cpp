// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lobject.h"

#include "lstate.h"
#include "lstring.h"
#include "lgc.h"
#include "ldo.h"
#include "lnumutils.h"

#include <ctype.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

const TValue luaO_nilobject_ = {{NULL}, {0}, LUA_TNIL};

int luaO_log2(unsigned int x)
{
    static const uint8_t log_2[256] = {0, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6,
                                       6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
                                       7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
                                       7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                                       8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                                       8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8,
                                       8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8};
    int l = -1;
    while (x >= 256)
    {
        l += 8;
        x >>= 8;
    }
    return l + log_2[x];
}

int luaO_rawequalObj(const TValue* t1, const TValue* t2)
{
    if (ttype(t1) != ttype(t2))
        return 0;
    else
        switch (ttype(t1))
        {
        case LUA_TNIL:
            return 1;
        case LUA_TNUMBER:
            return luai_numeq(nvalue(t1), nvalue(t2));
        case LUA_TINTEGER:
            return luai_inteq(lvalue(t1), lvalue(t2));
        case LUA_TVECTOR:
            return luai_veceq(vvalue(t1), vvalue(t2));
        case LUA_TBOOLEAN:
            return bvalue(t1) == bvalue(t2); // boolean true must be 1 !!
        case LUA_TLIGHTUSERDATA:
            return pvalue(t1) == pvalue(t2) && lightuserdatatag(t1) == lightuserdatatag(t2);
        default:
            LUAU_ASSERT(iscollectable(t1));
            return gcvalue(t1) == gcvalue(t2);
        }
}

int luaO_rawequalKey(const TKey* t1, const TValue* t2)
{
    if (ttype(t1) != ttype(t2))
        return 0;
    else
        switch (ttype(t1))
        {
        case LUA_TNIL:
            return 1;
        case LUA_TNUMBER:
            return luai_numeq(nvalue(t1), nvalue(t2));
        case LUA_TINTEGER:
            return luai_inteq(lvalue(t1), lvalue(t2));
        case LUA_TVECTOR:
            return luai_veceq(vvalue(t1), vvalue(t2));
        case LUA_TBOOLEAN:
            return bvalue(t1) == bvalue(t2); // boolean true must be 1 !!
        case LUA_TLIGHTUSERDATA:
            return pvalue(t1) == pvalue(t2) && lightuserdatatag(t1) == lightuserdatatag(t2);
        default:
            LUAU_ASSERT(iscollectable(t1));
            return gcvalue(t1) == gcvalue(t2);
        }
}

int luaO_str2d(const char* s, double* result)
{
    char* endptr;
    *result = luai_str2num(s, &endptr);
    if (endptr == s)
        return 0;                         // conversion failed
    if (*endptr == 'x' || *endptr == 'X') // maybe an hexadecimal constant?
        *result = cast_num(strtoul(s, &endptr, 16));
    if (*endptr == '\0')
        return 1; // most common case
    while (isspace(cast_to(unsigned char, *endptr)))
        endptr++;
    if (*endptr != '\0')
        return 0; // invalid trailing characters?
    return 1;
}

int luaO_str2l(const char* s, int64_t* result, int base)
{
    char* endptr = nullptr;
    if (base == 10)
    {
        *result = luai_str2long(s, &endptr, base);
        if (endptr == s)
            return 0;                         // conversion failed
        if (*endptr == 'x' || *endptr == 'X') // maybe an hexadecimal constant?
            *result = (int64_t)strtoull(s, &endptr, 16);
    }
    else
    {
        // unsigned parse in other bases
        *result = (int64_t)strtoull(s, &endptr, base);
        if (endptr == s)
            return 0;
    }
    if (*endptr == '\0')
        return 1; // most common case
    while (isspace(cast_to(unsigned char, *endptr)))
        endptr++;
    if (*endptr != '\0')
        return 0; // invalid trailing characters?
    return 1;
}

const char* luaO_pushvfstring(lua_State* L, const char* fmt, va_list argp)
{
    char result[LUA_BUFFERSIZE];
    vsnprintf(result, sizeof(result), fmt, argp);

    setsvalue(L, L->top, luaS_new(L, result));
    incr_top(L);
    return svalue(L->top - 1);
}

const char* luaO_pushfstring(lua_State* L, const char* fmt, ...)
{
    const char* msg;
    va_list argp;
    va_start(argp, fmt);
    msg = luaO_pushvfstring(L, fmt, argp);
    va_end(argp);
    return msg;
}

// Possible chunkname prefixes:
//
// '=' prefix: meant to represent custom chunknames. When truncation is needed,
// the beginning of the chunkname is kept.
//
// '@' prefix: meant to represent filepaths. When truncation is needed, the end
// of the filepath is kept, as this is more useful for identifying the file.
const char* luaO_chunkid(char* buf, size_t buflen, const char* source, size_t srclen)
{
    if (*source == '=')
    {
        if (srclen <= buflen)
            return source + 1;
        // truncate the part after =
        memcpy(buf, source + 1, buflen - 1);
        buf[buflen - 1] = '\0';
    }
    else if (*source == '@')
    {
        if (srclen <= buflen)
            return source + 1;
        // truncate the part after @
        memcpy(buf, "...", 3);
        memcpy(buf + 3, source + srclen - (buflen - 4), buflen - 4);
        buf[buflen - 1] = '\0';
    }
    else
    {                                         // buf = [string "string"]
        size_t len = strcspn(source, "\n\r"); // stop at first newline
        buflen -= sizeof("[string \"...\"]");
        if (len > buflen)
            len = buflen;
        strcpy(buf, "[string \"");
        if (source[len] != '\0')
        { // must truncate?
            strncat(buf, source, len);
            strcat(buf, "...");
        }
        else
            strcat(buf, source);
        strcat(buf, "\"]");
    }
    return buf;
}
