// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lualib.h"

#include "lcommon.h"

#include <string.h>
#include <time.h>

#define LUA_STRFTIMEOPTIONS "aAbBcdHIjmMpSUwWxXyYzZ%"

#if defined(_WIN32)
static tm* gmtime_r(const time_t* timep, tm* result)
{
    return gmtime_s(result, timep) == 0 ? result : NULL;
}

static tm* localtime_r(const time_t* timep, tm* result)
{
    return localtime_s(result, timep) == 0 ? result : NULL;
}
#endif

static time_t os_timegm(struct tm* timep)
{
    // Julian day number calculation
    int day = timep->tm_mday;
    int month = timep->tm_mon + 1;
    int year = timep->tm_year + 1900;

    // year adjustment, pretend that it starts in March
    int a = timep->tm_mon % 12 < 2 ? 1 : 0;

    // also adjust for out-of-range month numbers in input
    a -= timep->tm_mon / 12;

    int y = year + 4800 - a;
    int m = month + (12 * a) - 3;

    int julianday = day + ((153 * m + 2) / 5) + (365 * y) + (y / 4) - (y / 100) + (y / 400) - 32045;

    const int utcstartasjulianday = 2440588;                              // Jan 1st 1970 offset in Julian calendar
    const int64_t utcstartasjuliansecond = utcstartasjulianday * 86400ll; // same in seconds

    // fail the dates before UTC start
    if (julianday < utcstartasjulianday)
        return time_t(-1);

    int64_t daysecond = timep->tm_hour * 3600ll + timep->tm_min * 60ll + timep->tm_sec;
    int64_t julianseconds = int64_t(julianday) * 86400ull + daysecond;

    if (julianseconds < utcstartasjuliansecond)
        return time_t(-1);

    int64_t utc = julianseconds - utcstartasjuliansecond;
    return time_t(utc);
}

static int os_clock(lua_State* L)
{
    lua_pushnumber(L, lua_clock());
    return 1;
}

/*
** {======================================================
** Time/Date operations
** { year=%Y, month=%m, day=%d, hour=%H, min=%M, sec=%S,
**   wday=%w+1, yday=%j, isdst=? }
** =======================================================
*/

static void setfield(lua_State* L, const char* key, int value)
{
    lua_pushinteger(L, value);
    lua_setfield(L, -2, key);
}

static void setboolfield(lua_State* L, const char* key, int value)
{
    if (value < 0) // undefined?
        return;    // does not set field
    lua_pushboolean(L, value);
    lua_setfield(L, -2, key);
}

static int getboolfield(lua_State* L, const char* key)
{
    int res;
    lua_rawgetfield(L, -1, key);
    res = lua_isnil(L, -1) ? -1 : lua_toboolean(L, -1);
    lua_pop(L, 1);
    return res;
}

static int getfield(lua_State* L, const char* key, int d)
{
    int res;
    lua_rawgetfield(L, -1, key);
    if (lua_isnumber(L, -1))
        res = (int)lua_tointeger(L, -1);
    else
    {
        if (d < 0)
            luaL_error(L, "field '%s' missing in date table", key);
        res = d;
    }
    lua_pop(L, 1);
    return res;
}

static int os_date(lua_State* L)
{
    const char* s = luaL_optstring(L, 1, "%c");
    time_t t = luaL_opt(L, (time_t)luaL_checknumber, 2, time(NULL));

    struct tm tm;
    struct tm* stm;
    if (*s == '!')
    { // UTC?
        stm = gmtime_r(&t, &tm);
        s++; // skip `!'
    }
    else
    {
        // on Windows, localtime() fails with dates before epoch start so we disallow that
        stm = t < 0 ? NULL : localtime_r(&t, &tm);
    }

    if (stm == NULL) // invalid date?
    {
        lua_pushnil(L);
    }
    else if (strcmp(s, "*t") == 0)
    {
        lua_createtable(L, 0, 9); // 9 = number of fields
        setfield(L, "sec", stm->tm_sec);
        setfield(L, "min", stm->tm_min);
        setfield(L, "hour", stm->tm_hour);
        setfield(L, "day", stm->tm_mday);
        setfield(L, "month", stm->tm_mon + 1);
        setfield(L, "year", stm->tm_year + 1900);
        setfield(L, "wday", stm->tm_wday + 1);
        setfield(L, "yday", stm->tm_yday + 1);
        setboolfield(L, "isdst", stm->tm_isdst);
    }
    else
    {
        char cc[3];
        cc[0] = '%';
        cc[2] = '\0';

        luaL_Strbuf b;
        luaL_buffinit(L, &b);
        for (; *s; s++)
        {
            if (*s != '%' || *(s + 1) == '\0') // no conversion specifier?
            {
                luaL_addchar(&b, *s);
            }
            else if (strchr(LUA_STRFTIMEOPTIONS, *(s + 1)) == 0)
            {
                luaL_argerror(L, 1, "invalid conversion specifier");
            }
            else
            {
                size_t reslen;
                char buff[200]; // should be big enough for any conversion result
                cc[1] = *(++s);
                reslen = strftime(buff, sizeof(buff), cc, stm);
                luaL_addlstring(&b, buff, reslen);
            }
        }
        luaL_pushresult(&b);
    }
    return 1;
}

static int os_time(lua_State* L)
{
    time_t t;
    if (lua_isnoneornil(L, 1)) // called without args?
        t = time(NULL);        // get current time
    else
    {
        struct tm ts;
        luaL_checktype(L, 1, LUA_TTABLE);
        lua_settop(L, 1); // make sure table is at the top
        ts.tm_sec = getfield(L, "sec", 0);
        ts.tm_min = getfield(L, "min", 0);
        ts.tm_hour = getfield(L, "hour", 12);
        ts.tm_mday = getfield(L, "day", -1);
        ts.tm_mon = getfield(L, "month", -1) - 1;
        ts.tm_year = getfield(L, "year", -1) - 1900;
        ts.tm_isdst = getboolfield(L, "isdst");

        // Note: upstream Lua uses mktime() here which assumes input is local time, but we prefer UTC for consistency
        t = os_timegm(&ts);
    }
    if (t == (time_t)(-1))
        lua_pushnil(L);
    else
        lua_pushnumber(L, (double)t);
    return 1;
}

static int os_difftime(lua_State* L)
{
    lua_pushnumber(L, difftime((time_t)(luaL_checknumber(L, 1)), (time_t)(luaL_optnumber(L, 2, 0))));
    return 1;
}

static const luaL_Reg syslib[] = {
    {"clock", os_clock},
    {"date", os_date},
    {"difftime", os_difftime},
    {"time", os_time},
    {NULL, NULL},
};

int luaopen_os(lua_State* L)
{
    luaL_register(L, LUA_OSLIBNAME, syslib);
    return 1;
}
