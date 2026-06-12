// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details

#include "lclass.h"

#include "lfunc.h"
#include "lgc.h"
#include "lmem.h"
#include "lobject.h"
#include "lstate.h"
#include "lstring.h"
#include "ltable.h"
#include "ltm.h"
#include "lualib.h"
#include "lvm.h"

LuauClass* luaR_newclass(
    lua_State* L,
    TString* name,
    LuaTable* memberstooffset,
    TString** offsettomember,
    int numberofinstancemembers,
    int numberofstaticmembers
)
{
    LUAU_ASSERT(L->global->GCthreshold == SIZE_MAX && "GC must be paused");
    LuauClass* classobject = luaM_newgco(L, LuauClass, sizeof(LuauClass), L->activememcat);
    luaC_init(L, classobject, LUA_TCLASS);
    classobject->name = name;

    classobject->staticmembers = luaM_newarray(L, numberofstaticmembers, TValue, classobject->memcat);
    // Initialize static members to nil, otherwise we may read uninitialized memory.
    for (int i = 0; i < numberofstaticmembers; i++)
        setnilvalue(&classobject->staticmembers[i]);

    classobject->memberstooffset = memberstooffset;
    classobject->offsettomember = offsettomember;

    // Initialize the metatable of the _class object_, which for now only
    // contains an __call entry for the class constructor.
    classobject->metatable = luaH_new(L, 0, 1);
    // We should probably pass an empty table here rather than the global
    // environment.
    Closure* constructor = luaF_newCclosure(L, 0, L->gt);
    constructor->c.f = luaR_createobject;
    constructor->c.debugname = "luaR_createobject";
    constructor->c.cont = NULL;
    TValue* dest = luaH_setstr(L, classobject->metatable, L->global->tmname[TM_CALL]);
    LUAU_ASSERT(ttisnil(dest));
    setclvalue(L, dest, constructor);
    classobject->metatable->readonly = true;
    classobject->instancemetatable = NULL;

    classobject->numberofinstancemembers = numberofinstancemembers;
    classobject->numberofallmembers = numberofinstancemembers + numberofstaticmembers;

    return classobject;
}

void luaR_addclassmember(lua_State* L, LuauClass* classobject, TString* name, TValue* value)
{
    LUAU_ASSERT(classobject->staticmembers != nullptr);
    const TValue* offset = luaH_getstr(classobject->memberstooffset, name);
    LUAU_ASSERT(ttisnumber(offset));
    const int offsetint = int(nvalue(offset));
    LUAU_ASSERT(offsetint >= classobject->numberofinstancemembers && offsetint < classobject->numberofallmembers);
    LUAU_ASSERT(ttisfunction(value) && value->value.gc->gch.tt == LUA_TFUNCTION);
    setobj2class(L, &classobject->staticmembers[offsetint - classobject->numberofinstancemembers], value);
    luaC_barrier(L, classobject, value);

    // Only metamethods in the parser's allowlist are supported (see ALLOWED_METAMETHODS in Parser.cpp)
    bool isMetamethod = (name == luaS_newlstr(L, "__tostring", 10));
    for (int i = 0; i < TM_N && !isMetamethod; i++)
        isMetamethod = (name == L->global->tmname[i]);

    if (isMetamethod)
    {
        if (!classobject->instancemetatable)
        {
            classobject->instancemetatable = luaH_new(L, 0, 1);
            luaC_objbarrier(L, classobject, classobject->instancemetatable);
        }
        TValue* dest = luaH_setstr(L, classobject->instancemetatable, name);
        setobj2t(L, dest, value);
        luaC_barrier(L, classobject->instancemetatable, value);
    }
}

int luaR_createobject(lua_State* L)
{
    luaL_checktype(L, 1, LUA_TCLASS);
    LuauClass* classobject = classvalue(L->base);
    LuauObject* classinst = luaM_newgco(L, LuauObject, sizeof(LuauObject), L->activememcat);
    luaC_init(L, classinst, LUA_TOBJECT);
    classinst->lclass = classobject;
    classinst->numberofmembers = classobject->numberofinstancemembers;
    classinst->members = luaM_newarray(L, classinst->numberofmembers, TValue, L->activememcat);
    int numargs = lua_gettop(L);

    // We need to initialize all of the instance members to `nil` to start.
    for (int idx = 0; idx < classobject->numberofinstancemembers; idx++)
        setnilvalue(&classinst->members[idx]);

    // Push the class object onto the stack. We do this prior to setting the
    // fields as we may reallocate the stack as part of indexing into the
    // second argument (if present).
    setobjectvalue(L, L->top, classinst);
    L->top++;

    // Stack location to hold the table lookup result
    setnilvalue(L->top);
    L->top++;

    switch (numargs)
    {
    case 1:
        // If given no second argument, assume all class members are `nil`.
        break;
    case 2:
        // If given a second argument, use it to initialize all class members.
        for (int idx = 0; idx < classobject->numberofinstancemembers; idx++)
        {
            TValue key;
            setsvalue(L, &key, classobject->offsettomember[idx]);
            luaV_gettable(L, L->base + 1, &key, L->top - 1);
            setobj(L, &classinst->members[idx], L->top - 1);
        }
        break;
    default:
        luaL_error(L, "wrong number of arguments for constructing a '%s'", getstr(classobject->name));
    }

    L->top--;

    // Preserve the GC invariant, moving barrier back once after writing multiple objects (similar to SETLIST)
    luaC_barrierfast(L, classinst);

    return 1;
}


void luaR_freeclass(lua_State* L, LuauClass* classobject, lua_Page* page)
{
    luaM_freearray(
        L, classobject->staticmembers, classobject->numberofallmembers - classobject->numberofinstancemembers, TValue, classobject->memcat
    );
    luaM_freearray(L, classobject->offsettomember, classobject->numberofallmembers, TString*, classobject->memcat);
    luaM_freegco(L, classobject, sizeof(LuauClass), classobject->memcat, page);
}

void luaR_freeobject(lua_State* L, LuauObject* classinstance, lua_Page* page)
{
    luaM_freearray(L, classinstance->members, classinstance->numberofmembers, TValue, classinstance->memcat);
    luaM_freegco(L, classinstance, sizeof(LuauObject), classinstance->memcat, page);
}
