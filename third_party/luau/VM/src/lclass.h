// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include "lmem.h"
#include "lobject.h"

/**
 * Allocate and return a new class object.
 * @param name The name of this class. This does not have to be unique within a program.
 * @param memberstooffset A table mapping member names to their offset within the class
 * @param offsettomember An array of length `numberofinstancemembers + numberofstaticmembers` where
 * each entry is the name of the member at the specified offset.
 * @param numberofinstancemembers The number of instance members (fields) this class has.
 * @param numberofstaticmembers The number of static members (only methods today) this class has.
 */
LUAI_FUNC LuauClass* luaR_newclass(
    lua_State* L,
    TString* name,
    LuaTable* memberstooffset,
    TString** offsettomember,
    int numberofinstancemembers,
    int numberofstaticmembers
);

/**
 * Add a new class member to `classobject` named `name` and with value `method`. As the naming implies
 * we only support methods today.
 */
LUAI_FUNC void luaR_addclassmember(lua_State* L, LuauClass* classobject, TString* name, TValue* method);

LUAI_FUNC void luaR_freeclass(lua_State* L, LuauClass* classobject, lua_Page* page);

/**
 * Callback for creating class instances. This is written as a Lua API function and expects the stack to be:
 *
 *  [ BASE ]
 *  - A class object
 *  - An optional indexable value
 *
 * This function will allocate a new class instance, iterate over the instance members of the class object,
 * initialize each class instance member with the result of indexing into the value, and then assign the
 * value to the top of the stack. If the indexable is not present, all members are initialized to `nil`.
 */
LUAI_FUNC int luaR_createobject(lua_State* L);

LUAI_FUNC void luaR_freeobject(lua_State* L, LuauObject* classinstance, lua_Page* page);

#define luaR_checkoffsetinbounds(inst, offset) (int(offset) >= 0 && int(offset) < (inst)->lclass->numberofallmembers)

#define luaR_lookupmemberatoffset(inst, offset) \
    (LUAU_ASSERT(luaR_checkoffsetinbounds(inst, offset)), \
     offset < (inst)->lclass->numberofinstancemembers ? &(inst)->members[offset] \
                                                      : &(inst)->lclass->staticmembers[offset - inst->lclass->numberofinstancemembers])
