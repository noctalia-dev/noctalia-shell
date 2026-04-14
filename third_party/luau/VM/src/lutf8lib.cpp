// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lualib.h"

#include "lcommon.h"

#define MAXUNICODE 0x10FFFF

#define iscont(p) ((*(p) & 0xC0) == 0x80)

// from strlib
// translate a relative string position: negative means back from end
static int u_posrelat(int pos, size_t len)
{
    if (pos >= 0)
        return pos;
    else if (0u - (size_t)pos > len)
        return 0;
    else
        return (int)len + pos + 1;
}

/*
** Decode one UTF-8 sequence, returning NULL if byte sequence is invalid.
*/
static const char* utf8_decode(const char* o, int* val)
{
    static const unsigned int limits[] = {0xFF, 0x7F, 0x7FF, 0xFFFF};
    const unsigned char* s = (const unsigned char*)o;
    unsigned int c = s[0];
    unsigned int res = 0; // final result
    if (c < 0x80)         // ascii?
        res = c;
    else
    {
        int count = 0; // to count number of continuation bytes
        while (c & 0x40)
        {                                   // still have continuation bytes?
            int cc = s[++count];            // read next byte
            if ((cc & 0xC0) != 0x80)        // not a continuation byte?
                return NULL;                // invalid byte sequence
            res = (res << 6) | (cc & 0x3F); // add lower 6 bits from cont. byte
            c <<= 1;                        // to test next bit
        }
        res |= ((c & 0x7F) << (count * 5)); // add first byte
        if (count > 3 || res > MAXUNICODE || res <= limits[count])
            return NULL; // invalid byte sequence
        if (unsigned(res - 0xD800) < 0x800)
            return NULL; // surrogate
        s += count;      // skip continuation bytes read
    }
    if (val)
        *val = res;
    return (const char*)s + 1; // +1 to include first byte
}

/*
** utf8len(s [, i [, j]]) --> number of characters that start in the
** range [i,j], or nil + current position if 's' is not well formed in
** that interval
*/
static int utflen(lua_State* L)
{
    int n = 0;
    size_t len;
    const char* s = luaL_checklstring(L, 1, &len);
    int posi = u_posrelat(luaL_optinteger(L, 2, 1), len);
    int posj = u_posrelat(luaL_optinteger(L, 3, -1), len);
    luaL_argcheck(L, 1 <= posi && --posi <= (int)len, 2, "initial position out of string");
    luaL_argcheck(L, --posj < (int)len, 3, "final position out of string");
    while (posi <= posj)
    {
        const char* s1 = utf8_decode(s + posi, NULL);
        if (s1 == NULL)
        {                                 // conversion error?
            lua_pushnil(L);               // return nil ...
            lua_pushinteger(L, posi + 1); // ... and current position
            return 2;
        }
        posi = (int)(s1 - s);
        n++;
    }
    lua_pushinteger(L, n);
    return 1;
}

/*
** codepoint(s, [i, [j]])  -> returns codepoints for all characters
** that start in the range [i,j]
*/
static int codepoint(lua_State* L)
{
    size_t len;
    const char* s = luaL_checklstring(L, 1, &len);
    int posi = u_posrelat(luaL_optinteger(L, 2, 1), len);
    int pose = u_posrelat(luaL_optinteger(L, 3, posi), len);
    int n;
    const char* se;
    luaL_argcheck(L, posi >= 1, 2, "out of range");
    luaL_argcheck(L, pose <= (int)len, 3, "out of range");
    if (posi > pose)
        return 0;               // empty interval; return no values
    if (pose - posi >= INT_MAX) // (int -> int) overflow?
        luaL_error(L, "string slice too long");
    n = (int)(pose - posi) + 1;
    luaL_checkstack(L, n, "string slice too long");
    n = 0;
    se = s + pose;
    for (s += posi - 1; s < se;)
    {
        int code;
        s = utf8_decode(s, &code);
        if (s == NULL)
            luaL_error(L, "invalid UTF-8 code");
        lua_pushinteger(L, code);
        n++;
    }
    return n;
}

// from Lua 5.3 lobject.h
#define UTF8BUFFSZ 8

// from Lua 5.3 lobject.c, copied verbatim + static
static int luaO_utf8esc(char* buff, unsigned long x)
{
    int n = 1; // number of bytes put in buffer (backwards)
    LUAU_ASSERT(x <= 0x10FFFF);
    if (x < 0x80) // ascii?
        buff[UTF8BUFFSZ - 1] = cast_to(char, x);
    else
    {                            // need continuation bytes
        unsigned int mfb = 0x3f; // maximum that fits in first byte
        do
        { // add continuation bytes
            buff[UTF8BUFFSZ - (n++)] = cast_to(char, 0x80 | (x & 0x3f));
            x >>= 6;   // remove added bits
            mfb >>= 1; // now there is one less bit available in first byte
        } while (x > mfb); // still needs continuation byte?
        buff[UTF8BUFFSZ - n] = cast_to(char, (~mfb << 1) | x); // add first byte
    }
    return n;
}

// lighter replacement for pushutfchar; doesn't push any string onto the stack
static int buffutfchar(lua_State* L, int arg, char* buff, const char** charstr)
{
    int code = luaL_checkinteger(L, arg);
    luaL_argcheck(L, 0 <= code && code <= MAXUNICODE, arg, "value out of range");
    int l = luaO_utf8esc(buff, cast_to(long, code));
    *charstr = buff + UTF8BUFFSZ - l;
    return l;
}

/*
** utfchar(n1, n2, ...)  -> char(n1)..char(n2)...
**
** This version avoids the need to make more invasive upgrades elsewhere (like
** implementing the %U escape in lua_pushfstring) and avoids pushing string
** objects for each codepoint in the multi-argument case. -Jovanni
*/
static int utfchar(lua_State* L)
{
    char buff[UTF8BUFFSZ];
    const char* charstr;

    int n = lua_gettop(L); // number of arguments
    if (n == 1)
    { // optimize common case of single char
        int l = buffutfchar(L, 1, buff, &charstr);
        lua_pushlstring(L, charstr, l);
    }
    else
    {
        luaL_Strbuf b;
        luaL_buffinit(L, &b);
        for (int i = 1; i <= n; i++)
        {
            int l = buffutfchar(L, i, buff, &charstr);
            luaL_addlstring(&b, charstr, l);
        }
        luaL_pushresult(&b);
    }
    return 1;
}

/*
** offset(s, n, [i])  -> index where n-th character counting from
**   position 'i' starts; 0 means character at 'i'.
*/
static int byteoffset(lua_State* L)
{
    size_t len;
    const char* s = luaL_checklstring(L, 1, &len);
    int n = luaL_checkinteger(L, 2);
    int posi = (n >= 0) ? 1 : (int)len + 1;
    posi = u_posrelat(luaL_optinteger(L, 3, posi), len);
    luaL_argcheck(L, 1 <= posi && --posi <= (int)len, 3, "position out of range");
    if (n == 0)
    {
        // find beginning of current byte sequence
        while (posi > 0 && iscont(s + posi))
            posi--;
    }
    else
    {
        if (iscont(s + posi))
            luaL_error(L, "initial position is a continuation byte");
        if (n < 0)
        {
            while (n < 0 && posi > 0)
            { // move back
                do
                { // find beginning of previous character
                    posi--;
                } while (posi > 0 && iscont(s + posi));
                n++;
            }
        }
        else
        {
            n--; // do not move for 1st character
            while (n > 0 && posi < (int)len)
            {
                do
                { // find beginning of next character
                    posi++;
                } while (iscont(s + posi)); // (cannot pass final '\0')
                n--;
            }
        }
    }
    if (n == 0) // did it find given character?
        lua_pushinteger(L, posi + 1);
    else // no such character
        lua_pushnil(L);
    return 1;
}

static int iter_aux(lua_State* L)
{
    size_t len;
    const char* s = luaL_checklstring(L, 1, &len);
    int n = lua_tointeger(L, 2) - 1;
    if (n < 0) // first iteration?
        n = 0; // start from here
    else if (n < (int)len)
    {
        n++; // skip current byte
        while (iscont(s + n))
            n++; // and its continuations
    }
    if (n >= (int)len)
        return 0; // no more codepoints
    else
    {
        int code;
        const char* next = utf8_decode(s + n, &code);
        if (next == NULL || iscont(next))
            luaL_error(L, "invalid UTF-8 code");
        lua_pushinteger(L, n + 1);
        lua_pushinteger(L, code);
        return 2;
    }
}

static int iter_codes(lua_State* L)
{
    luaL_checkstring(L, 1);
    lua_pushcfunction(L, iter_aux, NULL);
    lua_pushvalue(L, 1);
    lua_pushinteger(L, 0);
    return 3;
}

// pattern to match a single UTF-8 character
#define UTF8PATT "[\0-\x7F\xC2-\xF4][\x80-\xBF]*"

static const luaL_Reg funcs[] = {
    {"offset", byteoffset},
    {"codepoint", codepoint},
    {"char", utfchar},
    {"len", utflen},
    {"codes", iter_codes},
    {NULL, NULL},
};

int luaopen_utf8(lua_State* L)
{
    luaL_register(L, LUA_UTF8LIBNAME, funcs);

    lua_pushlstring(L, UTF8PATT, sizeof(UTF8PATT) / sizeof(char) - 1);
    lua_setfield(L, -2, "charpattern");

    return 1;
}
