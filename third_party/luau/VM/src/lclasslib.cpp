#include "lapi.h"
#include "lobject.h"
#include "lua.h"
#include "lualib.h"
#include "lstate.h"


static int class_isinstance(lua_State* L)
{
    luaL_checkany(L, 1);
    luaL_checktype(L, 2, LUA_TCLASS);
    const TValue* inst = luaA_toobject(L, 1);
    const TValue* obj = luaA_toobject(L, 2);
    const LuauClass* lclass = classvalue(obj);
    bool isInstance = ttisobject(inst) && objectvalue(inst)->lclass == lclass;
    lua_pushboolean(L, isInstance);
    return 1;
}

static int class_classof(lua_State* L)
{
    luaL_checkany(L, 1);
    if (!lua_isobject(L, 1))
    {
        lua_pushnil(L);
        return 1;
    }
    const TValue* inst = luaA_toobject(L, 1);
    const LuauObject* ci = objectvalue(inst);
    luaA_pushclass(L, ci->lclass);
    return 1;
}

static const luaL_Reg classlib[] = {
    {"isinstance", class_isinstance},
    {"classof", class_classof},
    {nullptr, nullptr},
};

/*
** Open class library
*/
int luaopen_class(lua_State* L)
{
    luaL_register(L, LUA_CLASSLIBNAME, classlib);
    return 1;
}