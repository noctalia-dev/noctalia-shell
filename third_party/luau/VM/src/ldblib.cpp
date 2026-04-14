// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lualib.h"

#include "lvm.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>

static lua_State* getthread(lua_State* L, int* arg)
{
    if (lua_isthread(L, 1))
    {
        *arg = 1;
        return lua_tothread(L, 1);
    }
    else
    {
        *arg = 0;
        return L;
    }
}

static int db_info(lua_State* L)
{
    int arg;
    lua_State* L1 = getthread(L, &arg);
    int l1top = 0;

    // if L1 != L, L1 can be in any state, and therefore there are no guarantees about its stack space
    if (L != L1)
    {
        // for 'f' option, we reserve one slot and we also record the stack top
        lua_rawcheckstack(L1, 1);

        l1top = lua_gettop(L1);
    }

    int level;
    if (lua_isnumber(L, arg + 1))
    {
        level = (int)lua_tointeger(L, arg + 1);
        luaL_argcheck(L, level >= 0, arg + 1, "level can't be negative");
    }
    else if (arg == 0 && lua_isfunction(L, 1))
    {
        // convert absolute index to relative index
        level = -lua_gettop(L);
    }
    else
        luaL_argerror(L, arg + 1, "function or level expected");

    const char* options = luaL_checkstring(L, arg + 2);

    lua_Debug ar;
    if (!lua_getinfo(L1, level, options, &ar))
        return 0;

    int results = 0;
    bool occurs[26] = {};

    for (const char* it = options; *it; ++it)
    {
        if (unsigned(*it - 'a') < 26)
        {
            if (occurs[*it - 'a'])
            {
                // restore stack state of another thread as 'f' option might not have been visited yet
                if (L != L1)
                    lua_settop(L1, l1top);

                luaL_argerror(L, arg + 2, "duplicate option");
            }
            occurs[*it - 'a'] = true;
        }

        switch (*it)
        {
        case 's':
            lua_pushstring(L, ar.short_src);
            results++;
            break;

        case 'l':
            lua_pushinteger(L, ar.currentline);
            results++;
            break;

        case 'n':
            lua_pushstring(L, ar.name ? ar.name : "");
            results++;
            break;

        case 'f':
            if (L1 == L)
                lua_pushvalue(L, -1 - results); // function is right before results
            else
                lua_xmove(L1, L, 1); // function is at top of L1
            results++;
            break;

        case 'a':
            lua_pushinteger(L, ar.nparams);
            lua_pushboolean(L, ar.isvararg);
            results += 2;
            break;

        default:
            // restore stack state of another thread as 'f' option might not have been visited yet
            if (L != L1)
                lua_settop(L1, l1top);

            luaL_argerror(L, arg + 2, "invalid option");
        }
    }

    return results;
}

static int db_traceback(lua_State* L)
{
    int arg;
    lua_State* L1 = getthread(L, &arg);
    const char* msg = luaL_optstring(L, arg + 1, NULL);
    int level = luaL_optinteger(L, arg + 2, (L == L1) ? 1 : 0);
    luaL_argcheck(L, level >= 0, arg + 2, "level can't be negative");

    luaL_traceback(L, L1, msg, level);

    return 1;
}

static const luaL_Reg dblib[] = {
    {"info", db_info},
    {"traceback", db_traceback},
    {NULL, NULL},
};

int luaopen_debug(lua_State* L)
{
    luaL_register(L, LUA_DBLIBNAME, dblib);
    return 1;
}
