// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include "lobject.h"

#define sizeCclosure(n) (offsetof(Closure, c.upvals) + sizeof(TValue) * (n))
#define sizeLclosure(n) (offsetof(Closure, l.uprefs) + sizeof(TValue) * (n))

LUAI_FUNC Proto* luaF_newproto(lua_State* L);
LUAI_FUNC Closure* luaF_newLclosure(lua_State* L, int nelems, LuaTable* e, Proto* p);
LUAI_FUNC Closure* luaF_newCclosure(lua_State* L, int nelems, LuaTable* e);
LUAI_FUNC UpVal* luaF_findupval(lua_State* L, StkId level);
LUAI_FUNC void luaF_close(lua_State* L, StkId level);
LUAI_FUNC void luaF_closeupval(lua_State* L, UpVal* uv, bool dead);
LUAI_FUNC void luaF_freeproto(lua_State* L, Proto* f, struct lua_Page* page);
LUAI_FUNC void luaF_freeclosure(lua_State* L, Closure* c, struct lua_Page* page);
LUAI_FUNC void luaF_freeupval(lua_State* L, UpVal* uv, struct lua_Page* page);
LUAI_FUNC const LocVar* luaF_getlocal(const Proto* func, int local_number, int pc);
LUAI_FUNC const LocVar* luaF_findlocal(const Proto* func, int local_reg, int pc);
