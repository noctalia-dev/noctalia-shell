// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include "lobject.h"
#include "lstate.h"

// string size limit
#define MAXSSIZE (1 << 30)

// string atoms are not defined by default; the storage is 16-bit integer
#define ATOM_UNDEF -32768

#define sizestring(len) (offsetof(TString, data) + len + 1)

#define luaS_new(L, s) (luaS_newlstr(L, s, strlen(s)))
#define luaS_newliteral(L, s) (luaS_newlstr(L, "" s, (sizeof(s) / sizeof(char)) - 1))

#define luaS_fix(s) l_setbit((s)->marked, FIXEDBIT)

#define luaS_updateatom(L, ts) \
    { \
        if (ts->atom == ATOM_UNDEF) \
            ts->atom = L->global->cb.useratom ? L->global->cb.useratom(L, ts->data, ts->len) : -1; \
    }

LUAI_FUNC unsigned int luaS_hash(const char* str, size_t len);

LUAI_FUNC void luaS_resize(lua_State* L, int newsize);

LUAI_FUNC TString* luaS_newlstr(lua_State* L, const char* str, size_t l);
LUAI_FUNC void luaS_free(lua_State* L, TString* ts, struct lua_Page* page);

LUAI_FUNC TString* luaS_bufstart(lua_State* L, size_t size);
LUAI_FUNC TString* luaS_buffinish(lua_State* L, TString* ts);
