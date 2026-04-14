// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lapi.h"

#include "lstate.h"
#include "lstring.h"
#include "ltable.h"
#include "lfunc.h"
#include "lgc.h"
#include "ldo.h"
#include "ltm.h"
#include "ludata.h"
#include "lvm.h"
#include "lnumutils.h"
#include "lbuffer.h"

#include <string.h>

/*
 * This file contains most implementations of core Lua APIs from lua.h.
 *
 * These implementations should use api_check macros to verify that stack and type contracts hold; it's the callers
 * responsibility to, for example, pass a valid table index to lua_rawgetfield. Generally errors should only be raised
 * for conditions caller can't predict such as an out-of-memory error.
 *
 * The caller is expected to handle stack reservation (by using less than LUA_MINSTACK slots or by calling lua_checkstack).
 * To ensure this is handled correctly, use api_incr_top(L) when pushing values to the stack.
 *
 * Functions that push any collectable objects to the stack *should* call luaC_threadbarrier. Failure to do this can result
 * in stack references that point to dead objects since black threads don't get rescanned.
 *
 * Functions that push newly created objects to the stack *should* call luaC_checkGC in addition to luaC_threadbarrier.
 * Failure to do this can result in OOM since GC may never run.
 *
 * Note that luaC_checkGC may mark the thread and paint it black; functions that call both before pushing objects must
 * therefore call luaC_checkGC before luaC_threadbarrier to guarantee the object is pushed to a gray thread.
 */

const char* lua_ident = "$Lua: Lua 5.1.4 Copyright (C) 1994-2008 Lua.org, PUC-Rio $\n"
                        "$Authors: R. Ierusalimschy, L. H. de Figueiredo & W. Celes $\n"
                        "$URL: www.lua.org $\n";

const char* luau_ident = "$Luau: Copyright (C) 2019-2024 Roblox Corporation $\n"
                         "$URL: luau.org $\n";

#define api_checknelems(L, n) api_check(L, (n) <= (L->top - L->base))

#define api_checkvalidindex(L, i) api_check(L, (i) != luaO_nilobject)

#define api_incr_top(L) \
    { \
        api_check(L, L->top < L->ci->top); \
        L->top++; \
    }

#define api_update_top(L, p) \
    { \
        api_check(L, p >= L->base && p <= L->ci->top); \
        L->top = p; \
    }

static LuaTable* getcurrenv(lua_State* L)
{
    if (L->ci == L->base_ci) // no enclosing function?
        return L->gt;        // use global table as environment
    else
        return curr_func(L)->env;
}

static LUAU_NOINLINE TValue* pseudo2addr(lua_State* L, int idx)
{
    api_check(L, lua_ispseudo(idx));
    switch (idx)
    { // pseudo-indices
    case LUA_REGISTRYINDEX:
        return registry(L);
    case LUA_ENVIRONINDEX:
    {
        sethvalue(L, &L->global->pseudotemp, getcurrenv(L));
        return &L->global->pseudotemp;
    }
    case LUA_GLOBALSINDEX:
    {
        sethvalue(L, &L->global->pseudotemp, L->gt);
        return &L->global->pseudotemp;
    }
    default:
    {
        Closure* func = curr_func(L);
        idx = LUA_GLOBALSINDEX - idx;
        return (idx <= func->nupvalues) ? &func->c.upvals[idx - 1] : cast_to(TValue*, luaO_nilobject);
    }
    }
}

static LUAU_FORCEINLINE TValue* index2addr(lua_State* L, int idx)
{
    if (idx > 0)
    {
        TValue* o = L->base + (idx - 1);
        api_check(L, idx <= L->ci->top - L->base);
        if (o >= L->top)
            return cast_to(TValue*, luaO_nilobject);
        else
            return o;
    }
    else if (idx > LUA_REGISTRYINDEX)
    {
        api_check(L, idx != 0 && -idx <= L->top - L->base);
        return L->top + idx;
    }
    else
    {
        return pseudo2addr(L, idx);
    }
}

const TValue* luaA_toobject(lua_State* L, int idx)
{
    StkId p = index2addr(L, idx);
    return (p == luaO_nilobject) ? NULL : p;
}

void luaA_pushobject(lua_State* L, const TValue* o)
{
    setobj2s(L, L->top, o);
    api_incr_top(L);
}

int lua_checkstack(lua_State* L, int size)
{
    int res = 1;
    if (size > LUAI_MAXCSTACK || (L->top - L->base + size) > LUAI_MAXCSTACK)
        res = 0; // stack overflow
    else if (size > 0)
    {
        if (stacklimitreached(L, size))
        {
            struct CallContext
            {
                int size;

                static void run(lua_State* L, void* ud)
                {
                    CallContext* ctx = (CallContext*)ud;

                    luaD_growstack(L, ctx->size);
                }
            } ctx = {size};

            // there could be no memory to extend the stack
            if (luaD_rawrunprotected(L, &CallContext::run, &ctx) != LUA_OK)
                return 0;
        }
        else
        {
            condhardstacktests(luaD_reallocstack(L, L->stacksize - EXTRA_STACK, 0));
        }

        expandstacklimit(L, L->top + size);
    }
    return res;
}

void lua_rawcheckstack(lua_State* L, int size)
{
    luaD_checkstack(L, size);
    expandstacklimit(L, L->top + size);
}

void lua_xmove(lua_State* from, lua_State* to, int n)
{
    if (from == to)
        return;
    api_checknelems(from, n);
    api_check(from, from->global == to->global);
    api_check(from, to->ci->top - to->top >= n);
    luaC_threadbarrier(to);

    StkId ttop = to->top;
    StkId ftop = from->top - n;
    for (int i = 0; i < n; i++)
        setobj2s(to, ttop + i, ftop + i);

    from->top = ftop;
    to->top = ttop + n;
}

void lua_xpush(lua_State* from, lua_State* to, int idx)
{
    api_check(from, from->global == to->global);
    luaC_threadbarrier(to);
    setobj2s(to, to->top, index2addr(from, idx));
    api_incr_top(to);
}

lua_State* lua_newthread(lua_State* L)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    lua_State* L1 = luaE_newthread(L);
    setthvalue(L, L->top, L1);
    api_incr_top(L);
    global_State* g = L->global;
    if (g->cb.userthread)
        g->cb.userthread(L, L1);
    return L1;
}

lua_State* lua_mainthread(lua_State* L)
{
    return L->global->mainthread;
}

/*
** basic stack manipulation
*/

int lua_absindex(lua_State* L, int idx)
{
    api_check(L, (idx > 0 && idx <= L->top - L->base) || (idx < 0 && -idx <= L->top - L->base) || lua_ispseudo(idx));
    return idx > 0 || lua_ispseudo(idx) ? idx : cast_int(L->top - L->base) + idx + 1;
}

int lua_gettop(lua_State* L)
{
    return cast_int(L->top - L->base);
}

void lua_settop(lua_State* L, int idx)
{
    if (idx >= 0)
    {
        api_check(L, idx <= L->stack_last - L->base);
        while (L->top < L->base + idx)
            setnilvalue(L->top++);
        L->top = L->base + idx;
    }
    else
    {
        api_check(L, -(idx + 1) <= (L->top - L->base));
        L->top += idx + 1; // `subtract' index (index is negative)
    }
}

void lua_remove(lua_State* L, int idx)
{
    StkId p = index2addr(L, idx);
    api_checkvalidindex(L, p);
    while (++p < L->top)
        setobj2s(L, p - 1, p);
    L->top--;
}

void lua_insert(lua_State* L, int idx)
{
    luaC_threadbarrier(L);
    StkId p = index2addr(L, idx);
    api_checkvalidindex(L, p);
    for (StkId q = L->top; q > p; q--)
        setobj2s(L, q, q - 1);
    setobj2s(L, p, L->top);
}

void lua_replace(lua_State* L, int idx)
{
    api_checknelems(L, 1);
    luaC_threadbarrier(L);
    StkId o = index2addr(L, idx);
    api_checkvalidindex(L, o);
    if (idx == LUA_ENVIRONINDEX)
    {
        api_check(L, L->ci != L->base_ci);
        Closure* func = curr_func(L);
        api_check(L, ttistable(L->top - 1));
        func->env = hvalue(L->top - 1);
        luaC_barrier(L, func, L->top - 1);
    }
    else if (idx == LUA_GLOBALSINDEX)
    {
        api_check(L, ttistable(L->top - 1));
        L->gt = hvalue(L->top - 1);
    }
    else
    {
        setobj(L, o, L->top - 1);
        if (idx < LUA_GLOBALSINDEX) // function upvalue?
            luaC_barrier(L, curr_func(L), L->top - 1);
    }
    L->top--;
}

void lua_pushvalue(lua_State* L, int idx)
{
    luaC_threadbarrier(L);
    StkId o = index2addr(L, idx);
    setobj2s(L, L->top, o);
    api_incr_top(L);
}

/*
** access functions (stack -> C)
*/

int lua_type(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    return (o == luaO_nilobject) ? LUA_TNONE : ttype(o);
}

const char* lua_typename(lua_State* L, int t)
{
    return (t == LUA_TNONE) ? "no value" : luaT_typenames[t];
}

int lua_iscfunction(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    return iscfunction(o);
}

int lua_isLfunction(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    return isLfunction(o);
}

int lua_isnumber(lua_State* L, int idx)
{
    TValue n;
    const TValue* o = index2addr(L, idx);
    return tonumber(o, &n);
}

int lua_isstring(lua_State* L, int idx)
{
    int t = lua_type(L, idx);
    return (t == LUA_TSTRING || t == LUA_TNUMBER);
}

int lua_isuserdata(lua_State* L, int idx)
{
    const TValue* o = index2addr(L, idx);
    return (ttisuserdata(o) || ttislightuserdata(o));
}

int lua_rawequal(lua_State* L, int index1, int index2)
{
    StkId o1 = index2addr(L, index1);
    StkId o2 = index2addr(L, index2);
    return (o1 == luaO_nilobject || o2 == luaO_nilobject) ? 0 : luaO_rawequalObj(o1, o2);
}

int lua_equal(lua_State* L, int index1, int index2)
{
    StkId o1, o2;
    int i;
    o1 = index2addr(L, index1);
    o2 = index2addr(L, index2);
    i = (o1 == luaO_nilobject || o2 == luaO_nilobject) ? 0 : equalobj(L, o1, o2);
    return i;
}

int lua_lessthan(lua_State* L, int index1, int index2)
{
    StkId o1, o2;
    int i;
    o1 = index2addr(L, index1);
    o2 = index2addr(L, index2);
    i = (o1 == luaO_nilobject || o2 == luaO_nilobject) ? 0 : luaV_lessthan(L, o1, o2);
    return i;
}

double lua_tonumberx(lua_State* L, int idx, int* isnum)
{
    TValue n;
    const TValue* o = index2addr(L, idx);
    if (tonumber(o, &n))
    {
        if (isnum)
            *isnum = 1;
        return nvalue(o);
    }
    else
    {
        if (isnum)
            *isnum = 0;
        return 0;
    }
}

int lua_tointegerx(lua_State* L, int idx, int* isnum)
{
    TValue n;
    const TValue* o = index2addr(L, idx);
    if (tonumber(o, &n))
    {
        int res;
        double num = nvalue(o);
        luai_num2int(res, num);
        if (isnum)
            *isnum = 1;
        return res;
    }
    else
    {
        if (isnum)
            *isnum = 0;
        return 0;
    }
}

unsigned lua_tounsignedx(lua_State* L, int idx, int* isnum)
{
    TValue n;
    const TValue* o = index2addr(L, idx);
    if (tonumber(o, &n))
    {
        unsigned res;
        double num = nvalue(o);
        luai_num2unsigned(res, num);
        if (isnum)
            *isnum = 1;
        return res;
    }
    else
    {
        if (isnum)
            *isnum = 0;
        return 0;
    }
}

int lua_toboolean(lua_State* L, int idx)
{
    const TValue* o = index2addr(L, idx);
    return !l_isfalse(o);
}

int64_t lua_tointeger64(lua_State* L, int idx, int* isinteger)
{
    const TValue* o = index2addr(L, idx);
    if (ttisinteger(o))
    {
        if (isinteger)
            *isinteger = 1;
        return lvalue(o);
    }
    else
    {
        if (isinteger)
            *isinteger = 0;
        return 0;
    }
}

const char* lua_tolstring(lua_State* L, int idx, size_t* len)
{
    StkId o = index2addr(L, idx);
    if (!ttisstring(o))
    {
        luaC_threadbarrier(L);
        if (!luaV_tostring(L, o))
        { // conversion failed?
            if (len != NULL)
                *len = 0;
            return NULL;
        }
        luaC_checkGC(L);
        o = index2addr(L, idx); // previous call may reallocate the stack
    }
    if (len != NULL)
        *len = tsvalue(o)->len;
    return svalue(o);
}

const char* lua_tostringatom(lua_State* L, int idx, int* atom)
{
    StkId o = index2addr(L, idx);
    if (!ttisstring(o))
        return NULL;
    TString* s = tsvalue(o);
    if (atom)
    {
        luaS_updateatom(L, s);
        *atom = s->atom;
    }
    return getstr(s);
}

const char* lua_tolstringatom(lua_State* L, int idx, size_t* len, int* atom)
{
    StkId o = index2addr(L, idx);

    if (!ttisstring(o))
    {
        if (len)
            *len = 0;
        return NULL;
    }

    TString* s = tsvalue(o);
    if (len)
        *len = s->len;
    if (atom)
    {
        luaS_updateatom(L, s);
        *atom = s->atom;
    }

    return getstr(s);
}

const char* lua_namecallatom(lua_State* L, int* atom)
{
    TString* s = L->namecall;
    if (!s)
        return NULL;
    if (atom)
    {
        luaS_updateatom(L, s);
        *atom = s->atom;
    }
    return getstr(s);
}

const float* lua_tovector(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    if (!ttisvector(o))
        return NULL;
    return vvalue(o);
}

int lua_objlen(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    switch (ttype(o))
    {
    case LUA_TSTRING:
        return tsvalue(o)->len;
    case LUA_TUSERDATA:
        return uvalue(o)->len;
    case LUA_TBUFFER:
        return bufvalue(o)->len;
    case LUA_TTABLE:
        return luaH_getn(hvalue(o));
    default:
        return 0;
    }
}

lua_CFunction lua_tocfunction(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    return (!iscfunction(o)) ? NULL : cast_to(lua_CFunction, clvalue(o)->c.f);
}

void* lua_tolightuserdata(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    return (!ttislightuserdata(o)) ? NULL : pvalue(o);
}

void* lua_tolightuserdatatagged(lua_State* L, int idx, int tag)
{
    StkId o = index2addr(L, idx);
    return (!ttislightuserdata(o) || lightuserdatatag(o) != tag) ? NULL : pvalue(o);
}

void* lua_touserdata(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    if (ttisuserdata(o))
        return uvalue(o)->data;
    else if (ttislightuserdata(o))
        return pvalue(o);
    else
        return NULL;
}

void* lua_touserdatatagged(lua_State* L, int idx, int tag)
{
    StkId o = index2addr(L, idx);
    return (ttisuserdata(o) && uvalue(o)->tag == tag) ? uvalue(o)->data : NULL;
}

int lua_userdatatag(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    if (ttisuserdata(o))
        return uvalue(o)->tag;
    return -1;
}

int lua_lightuserdatatag(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    if (ttislightuserdata(o))
        return lightuserdatatag(o);
    return -1;
}

lua_State* lua_tothread(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    return (!ttisthread(o)) ? NULL : thvalue(o);
}

void* lua_tobuffer(lua_State* L, int idx, size_t* len)
{
    StkId o = index2addr(L, idx);

    if (!ttisbuffer(o))
        return NULL;

    Buffer* b = bufvalue(o);

    if (len)
        *len = b->len;

    return b->data;
}

const void* lua_topointer(lua_State* L, int idx)
{
    StkId o = index2addr(L, idx);
    switch (ttype(o))
    {
    case LUA_TUSERDATA:
        return uvalue(o)->data;
    case LUA_TLIGHTUSERDATA:
        return pvalue(o);
    default:
        return iscollectable(o) ? gcvalue(o) : NULL;
    }
}

/*
** push functions (C -> stack)
*/

void lua_pushnil(lua_State* L)
{
    setnilvalue(L->top);
    api_incr_top(L);
}

void lua_pushnumber(lua_State* L, double n)
{
    setnvalue(L->top, n);
    api_incr_top(L);
}

void lua_pushinteger(lua_State* L, int n)
{
    setnvalue(L->top, cast_num(n));
    api_incr_top(L);
}

void lua_pushinteger64(lua_State* L, int64_t n)
{
    setlvalue(L->top, n);
    api_incr_top(L);
}

void lua_pushunsigned(lua_State* L, unsigned u)
{
    setnvalue(L->top, cast_num(u));
    api_incr_top(L);
}

#if LUA_VECTOR_SIZE == 4
void lua_pushvector(lua_State* L, float x, float y, float z, float w)
{
    setvvalue(L->top, x, y, z, w);
    api_incr_top(L);
}
#else
void lua_pushvector(lua_State* L, float x, float y, float z)
{
    setvvalue(L->top, x, y, z, 0.0f);
    api_incr_top(L);
}
#endif

void lua_pushlstring(lua_State* L, const char* s, size_t len)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    setsvalue(L, L->top, luaS_newlstr(L, s, len));
    api_incr_top(L);
}

void lua_pushstring(lua_State* L, const char* s)
{
    if (s == NULL)
        lua_pushnil(L);
    else
        lua_pushlstring(L, s, strlen(s));
}

const char* lua_pushvfstring(lua_State* L, const char* fmt, va_list argp)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    const char* ret = luaO_pushvfstring(L, fmt, argp);
    return ret;
}

const char* lua_pushfstringL(lua_State* L, const char* fmt, ...)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    va_list argp;
    va_start(argp, fmt);
    const char* ret = luaO_pushvfstring(L, fmt, argp);
    va_end(argp);
    return ret;
}

void lua_pushcclosurek(lua_State* L, lua_CFunction fn, const char* debugname, int nup, lua_Continuation cont)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    api_checknelems(L, nup);
    Closure* cl = luaF_newCclosure(L, nup, getcurrenv(L));
    cl->c.f = fn;
    cl->c.cont = cont;
    cl->c.debugname = debugname;
    L->top -= nup;
    while (nup--)
        setobj2n(L, &cl->c.upvals[nup], L->top + nup);
    setclvalue(L, L->top, cl);
    LUAU_ASSERT(iswhite(obj2gco(cl)));
    api_incr_top(L);
}

void lua_pushboolean(lua_State* L, int b)
{
    setbvalue(L->top, (b != 0)); // ensure that true is 1
    api_incr_top(L);
}

void lua_pushlightuserdatatagged(lua_State* L, void* p, int tag)
{
    api_check(L, unsigned(tag) < LUA_LUTAG_LIMIT);
    setpvalue(L->top, p, tag);
    api_incr_top(L);
}

int lua_pushthread(lua_State* L)
{
    luaC_threadbarrier(L);
    setthvalue(L, L->top, L);
    api_incr_top(L);
    return L->global->mainthread == L;
}

/*
** get functions (Lua -> stack)
*/

int lua_gettable(lua_State* L, int idx)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_checkvalidindex(L, t);
    luaV_gettable(L, t, L->top - 1, L->top - 1);
    return ttype(L->top - 1);
}

int lua_getfield(lua_State* L, int idx, const char* k)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_checkvalidindex(L, t);
    TValue key;
    setsvalue(L, &key, luaS_new(L, k));
    luaV_gettable(L, t, &key, L->top);
    api_incr_top(L);
    return ttype(L->top - 1);
}

int lua_rawgetfield(lua_State* L, int idx, const char* k)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    TValue key;
    setsvalue(L, &key, luaS_new(L, k));
    setobj2s(L, L->top, luaH_getstr(hvalue(t), tsvalue(&key)));
    api_incr_top(L);
    return ttype(L->top - 1);
}

int lua_rawget(lua_State* L, int idx)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    setobj2s(L, L->top - 1, luaH_get(hvalue(t), L->top - 1));
    return ttype(L->top - 1);
}

int lua_rawgeti(lua_State* L, int idx, int n)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    setobj2s(L, L->top, luaH_getnum(hvalue(t), n));
    api_incr_top(L);
    return ttype(L->top - 1);
}

int lua_rawgetptagged(lua_State* L, int idx, void* p, int tag)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    setobj2s(L, L->top, luaH_getp(hvalue(t), p, tag));
    api_incr_top(L);
    return ttype(L->top - 1);
}

void lua_createtable(lua_State* L, int narray, int nrec)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    sethvalue(L, L->top, luaH_new(L, narray, nrec));
    api_incr_top(L);
}

void lua_setreadonly(lua_State* L, int objindex, int enabled)
{
    const TValue* o = index2addr(L, objindex);
    api_check(L, ttistable(o));
    LuaTable* t = hvalue(o);
    api_check(L, t != hvalue(registry(L)));
    t->readonly = bool(enabled);
}

int lua_getreadonly(lua_State* L, int objindex)
{
    const TValue* o = index2addr(L, objindex);
    api_check(L, ttistable(o));
    LuaTable* t = hvalue(o);
    int res = t->readonly;
    return res;
}

void lua_setsafeenv(lua_State* L, int objindex, int enabled)
{
    const TValue* o = index2addr(L, objindex);
    api_check(L, ttistable(o));
    LuaTable* t = hvalue(o);
    t->safeenv = bool(enabled);
}

int lua_getmetatable(lua_State* L, int objindex)
{
    luaC_threadbarrier(L);
    LuaTable* mt = NULL;
    const TValue* obj = index2addr(L, objindex);
    switch (ttype(obj))
    {
    case LUA_TTABLE:
        mt = hvalue(obj)->metatable;
        break;
    case LUA_TUSERDATA:
        mt = uvalue(obj)->metatable;
        break;
    default:
        mt = L->global->mt[ttype(obj)];
        break;
    }
    if (mt)
    {
        sethvalue(L, L->top, mt);
        api_incr_top(L);
    }
    return mt != NULL;
}

void lua_getfenv(lua_State* L, int idx)
{
    luaC_threadbarrier(L);
    StkId o = index2addr(L, idx);
    api_checkvalidindex(L, o);
    switch (ttype(o))
    {
    case LUA_TFUNCTION:
        sethvalue(L, L->top, clvalue(o)->env);
        break;
    case LUA_TTHREAD:
        sethvalue(L, L->top, thvalue(o)->gt);
        break;
    default:
        setnilvalue(L->top);
        break;
    }
    api_incr_top(L);
}

/*
** set functions (stack -> Lua)
*/

void lua_settable(lua_State* L, int idx)
{
    api_checknelems(L, 2);
    StkId t = index2addr(L, idx);
    api_checkvalidindex(L, t);
    luaV_settable(L, t, L->top - 2, L->top - 1);
    L->top -= 2; // pop index and value
}

void lua_setfield(lua_State* L, int idx, const char* k)
{
    api_checknelems(L, 1);
    StkId t = index2addr(L, idx);
    api_checkvalidindex(L, t);
    TValue key;
    setsvalue(L, &key, luaS_new(L, k));
    luaV_settable(L, t, &key, L->top - 1);
    L->top--;
}

void lua_rawsetfield(lua_State* L, int idx, const char* k)
{
    api_checknelems(L, 1);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    if (hvalue(t)->readonly)
        luaG_readonlyerror(L);
    setobj2t(L, luaH_setstr(L, hvalue(t), luaS_new(L, k)), L->top - 1);
    luaC_barriert(L, hvalue(t), L->top - 1);
    L->top--;
}

void lua_rawset(lua_State* L, int idx)
{
    api_checknelems(L, 2);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    if (hvalue(t)->readonly)
        luaG_readonlyerror(L);
    setobj2t(L, luaH_set(L, hvalue(t), L->top - 2), L->top - 1);
    luaC_barriert(L, hvalue(t), L->top - 1);
    L->top -= 2;
}

void lua_rawseti(lua_State* L, int idx, int n)
{
    api_checknelems(L, 1);
    StkId o = index2addr(L, idx);
    api_check(L, ttistable(o));
    if (hvalue(o)->readonly)
        luaG_readonlyerror(L);
    setobj2t(L, luaH_setnum(L, hvalue(o), n), L->top - 1);
    luaC_barriert(L, hvalue(o), L->top - 1);
    L->top--;
}

void lua_rawsetptagged(lua_State* L, int idx, void* p, int tag)
{
    api_checknelems(L, 1);
    StkId o = index2addr(L, idx);
    api_check(L, ttistable(o));
    if (hvalue(o)->readonly)
        luaG_readonlyerror(L);
    setobj2t(L, luaH_setp(L, hvalue(o), p, tag), L->top - 1);
    luaC_barriert(L, hvalue(o), L->top - 1);
    L->top--;
}

int lua_setmetatable(lua_State* L, int objindex)
{
    api_checknelems(L, 1);
    TValue* obj = index2addr(L, objindex);
    api_checkvalidindex(L, obj);
    LuaTable* mt = NULL;
    if (!ttisnil(L->top - 1))
    {
        api_check(L, ttistable(L->top - 1));
        mt = hvalue(L->top - 1);
    }
    switch (ttype(obj))
    {
    case LUA_TTABLE:
    {
        if (hvalue(obj)->readonly)
            luaG_readonlyerror(L);
        hvalue(obj)->metatable = mt;
        if (mt)
            luaC_objbarrier(L, hvalue(obj), mt);
        break;
    }
    case LUA_TUSERDATA:
    {
        uvalue(obj)->metatable = mt;
        if (mt)
            luaC_objbarrier(L, uvalue(obj), mt);
        break;
    }
    default:
    {
        L->global->mt[ttype(obj)] = mt;
        break;
    }
    }
    L->top--;
    return 1;
}

int lua_setfenv(lua_State* L, int idx)
{
    int res = 1;
    api_checknelems(L, 1);
    StkId o = index2addr(L, idx);
    api_checkvalidindex(L, o);
    api_check(L, ttistable(L->top - 1));
    switch (ttype(o))
    {
    case LUA_TFUNCTION:
        clvalue(o)->env = hvalue(L->top - 1);
        break;
    case LUA_TTHREAD:
        thvalue(o)->gt = hvalue(L->top - 1);
        break;
    default:
        res = 0;
        break;
    }
    if (res)
    {
        luaC_objbarrier(L, &gcvalue(o)->gch, hvalue(L->top - 1));
    }
    L->top--;
    return res;
}

/*
** `load' and `call' functions (run Lua code)
*/

#define adjustresults(L, nres) \
    { \
        if (nres == LUA_MULTRET && L->top >= L->ci->top) \
            L->ci->top = L->top; \
    }

#define checkresults(L, na, nr) api_check(L, (nr) == LUA_MULTRET || (L->ci->top - L->top >= (nr) - (na)))

void lua_call(lua_State* L, int nargs, int nresults)
{
    StkId func;
    api_checknelems(L, nargs + 1);
    api_check(L, L->status == 0);
    checkresults(L, nargs, nresults);
    func = L->top - (nargs + 1);

    luaD_call(L, func, nresults);

    adjustresults(L, nresults);
}

/*
** Execute a protected call.
*/
// data to `f_call'
struct CallS
{
    StkId func;
    int nresults;
};

static void f_call(lua_State* L, void* ud)
{
    struct CallS* c = cast_to(struct CallS*, ud);
    luaD_call(L, c->func, c->nresults);
}

int lua_pcall(lua_State* L, int nargs, int nresults, int errfunc)
{
    api_checknelems(L, nargs + 1);
    api_check(L, L->status == 0);
    checkresults(L, nargs, nresults);
    ptrdiff_t func = 0;
    if (errfunc != 0)
    {
        StkId o = index2addr(L, errfunc);
        api_checkvalidindex(L, o);
        func = savestack(L, o);
    }
    struct CallS c;
    c.func = L->top - (nargs + 1); // function to be called
    c.nresults = nresults;

    int status = luaD_pcall(L, f_call, &c, savestack(L, c.func), func);

    adjustresults(L, nresults);
    return status;
}

/*
** Execute a protected C call.
*/
// data to `f_Ccall'
struct CCallS
{
    lua_CFunction func;
    void* ud;
};

static void f_Ccall(lua_State* L, void* ud)
{
    struct CCallS* c = cast_to(struct CCallS*, ud);

    if (!lua_checkstack(L, 2))
        luaG_runerror(L, "stack limit");

    lua_pushcclosurek(L, c->func, nullptr, 0, nullptr);
    lua_pushlightuserdata(L, c->ud);
    luaD_call(L, L->top - 2, 0);
}

int lua_cpcall(lua_State* L, lua_CFunction func, void* ud)
{
    api_check(L, L->status == 0);

    struct CCallS c;
    c.func = func;
    c.ud = ud;

    return luaD_pcall(L, f_Ccall, &c, savestack(L, L->top), 0);
}

int lua_status(lua_State* L)
{
    return L->status;
}

int lua_costatus(lua_State* L, lua_State* co)
{
    if (co == L)
        return LUA_CORUN;
    if (co->status == LUA_YIELD)
        return LUA_COSUS;
    if (co->status == LUA_BREAK)
        return LUA_CONOR;
    if (co->status != 0) // some error occurred
        return LUA_COERR;
    if (co->ci != co->base_ci) // does it have frames?
        return LUA_CONOR;
    if (co->top == co->base)
        return LUA_COFIN;
    return LUA_COSUS; // initial state
}

void* lua_getthreaddata(lua_State* L)
{
    return L->userdata;
}

void lua_setthreaddata(lua_State* L, void* data)
{
    L->userdata = data;
}

/*
** Garbage-collection function
*/

int lua_gc(lua_State* L, int what, int data)
{
    int res = 0;
    condhardmemtests(luaC_validate(L), 1);
    global_State* g = L->global;
    switch (what)
    {
    case LUA_GCSTOP:
    {
        g->GCthreshold = SIZE_MAX;
        break;
    }
    case LUA_GCRESTART:
    {
        g->GCthreshold = g->totalbytes;
        break;
    }
    case LUA_GCCOLLECT:
    {
        luaC_fullgc(L);
        break;
    }
    case LUA_GCCOUNT:
    {
        // GC values are expressed in Kbytes: #bytes/2^10
        res = cast_int(g->totalbytes >> 10);
        break;
    }
    case LUA_GCCOUNTB:
    {
        res = cast_int(g->totalbytes & 1023);
        break;
    }
    case LUA_GCISRUNNING:
    {
        res = (g->GCthreshold != SIZE_MAX);
        break;
    }
    case LUA_GCSTEP:
    {
        size_t amount = (cast_to(size_t, data) << 10);
        ptrdiff_t oldcredit = g->gcstate == GCSpause ? 0 : g->GCthreshold - g->totalbytes;

        // temporarily adjust the threshold so that we can perform GC work
        if (amount <= g->totalbytes)
            g->GCthreshold = g->totalbytes - amount;
        else
            g->GCthreshold = 0;

#ifdef LUAI_GCMETRICS
        double startmarktime = g->gcmetrics.currcycle.marktime;
        double startsweeptime = g->gcmetrics.currcycle.sweeptime;
#endif

        // track how much work the loop will actually perform
        size_t actualwork = 0;

        while (g->GCthreshold <= g->totalbytes)
        {
            size_t stepsize = luaC_step(L, false);

            actualwork += stepsize;

            if (g->gcstate == GCSpause)
            {            // end of cycle?
                res = 1; // signal it
                break;
            }
        }

#ifdef LUAI_GCMETRICS
        // record explicit step statistics
        GCCycleMetrics* cyclemetrics = g->gcstate == GCSpause ? &g->gcmetrics.lastcycle : &g->gcmetrics.currcycle;

        double totalmarktime = cyclemetrics->marktime - startmarktime;
        double totalsweeptime = cyclemetrics->sweeptime - startsweeptime;

        if (totalmarktime > 0.0)
        {
            cyclemetrics->markexplicitsteps++;

            if (totalmarktime > cyclemetrics->markmaxexplicittime)
                cyclemetrics->markmaxexplicittime = totalmarktime;
        }

        if (totalsweeptime > 0.0)
        {
            cyclemetrics->sweepexplicitsteps++;

            if (totalsweeptime > cyclemetrics->sweepmaxexplicittime)
                cyclemetrics->sweepmaxexplicittime = totalsweeptime;
        }
#endif

        // if cycle hasn't finished, advance threshold forward for the amount of extra work performed
        if (g->gcstate != GCSpause)
        {
            // if a new cycle was triggered by explicit step, old 'credit' of GC work is 0
            ptrdiff_t newthreshold = g->totalbytes + actualwork + oldcredit;
            g->GCthreshold = newthreshold < 0 ? 0 : newthreshold;
        }
        break;
    }
    case LUA_GCSETGOAL:
    {
        res = g->gcgoal;
        g->gcgoal = data;
        break;
    }
    case LUA_GCSETSTEPMUL:
    {
        res = g->gcstepmul;
        g->gcstepmul = data;
        break;
    }
    case LUA_GCSETSTEPSIZE:
    {
        // GC values are expressed in Kbytes: #bytes/2^10
        res = g->gcstepsize >> 10;
        g->gcstepsize = data << 10;
        break;
    }
    default:
        res = -1; // invalid option
    }
    return res;
}

/*
** miscellaneous functions
*/

l_noret lua_error(lua_State* L)
{
    api_checknelems(L, 1);

    luaD_throw(L, LUA_ERRRUN);
}

int lua_next(lua_State* L, int idx)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    int more = luaH_next(L, hvalue(t), L->top - 1);
    if (more)
    {
        api_incr_top(L);
    }
    else             // no more elements
        L->top -= 1; // remove key
    return more;
}

int lua_rawiter(lua_State* L, int idx, int iter)
{
    luaC_threadbarrier(L);
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    api_check(L, iter >= 0);

    LuaTable* h = hvalue(t);
    int sizearray = h->sizearray;

    // first we advance iter through the array portion
    for (; unsigned(iter) < unsigned(sizearray); ++iter)
    {
        TValue* e = &h->array[iter];

        if (!ttisnil(e))
        {
            StkId top = L->top;
            setnvalue(top + 0, double(iter + 1));
            setobj2s(L, top + 1, e);
            api_update_top(L, top + 2);
            return iter + 1;
        }
    }

    int sizenode = 1 << h->lsizenode;

    // then we advance iter through the hash portion
    for (; unsigned(iter - sizearray) < unsigned(sizenode); ++iter)
    {
        LuaNode* n = &h->node[iter - sizearray];

        if (!ttisnil(gval(n)))
        {
            StkId top = L->top;
            getnodekey(L, top + 0, n);
            setobj2s(L, top + 1, gval(n));
            api_update_top(L, top + 2);
            return iter + 1;
        }
    }

    // traversal finished
    return -1;
}

void lua_concat(lua_State* L, int n)
{
    api_checknelems(L, n);
    if (n >= 2)
    {
        luaC_checkGC(L);
        luaC_threadbarrier(L);
        luaV_concat(L, n, cast_int(L->top - L->base) - 1);
        L->top -= (n - 1);
    }
    else if (n == 0)
    { // push empty string
        luaC_threadbarrier(L);
        setsvalue(L, L->top, luaS_newlstr(L, "", 0));
        api_incr_top(L);
    }
    // else n == 1; nothing to do
}

void* lua_newuserdatatagged(lua_State* L, size_t sz, int tag)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT || tag == UTAG_PROXY);
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    Udata* u = luaU_newudata(L, sz, tag);
    setuvalue(L, L->top, u);
    api_incr_top(L);
    return u->data;
}

void* lua_newuserdatataggedwithmetatable(lua_State* L, size_t sz, int tag)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT);
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    Udata* u = luaU_newudata(L, sz, tag);

    // currently, we always allocate unmarked objects, so forward barrier can be skipped
    LUAU_ASSERT(!isblack(obj2gco(u)));

    LuaTable* h = L->global->udatamt[tag];
    api_check(L, h != nullptr);

    u->metatable = h;

    setuvalue(L, L->top, u);
    api_incr_top(L);
    return u->data;
}

void* lua_newuserdatadtor(lua_State* L, size_t sz, void (*dtor)(void*))
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    // make sure sz + sizeof(dtor) doesn't overflow; luaU_newdata will reject SIZE_MAX correctly
    size_t as = sz < SIZE_MAX - sizeof(dtor) ? sz + sizeof(dtor) : SIZE_MAX;
    Udata* u = luaU_newudata(L, as, UTAG_IDTOR);
    memcpy(&u->data + sz, &dtor, sizeof(dtor));
    setuvalue(L, L->top, u);
    api_incr_top(L);
    return u->data;
}

void* lua_newbuffer(lua_State* L, size_t sz)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    Buffer* b = luaB_newbuffer(L, sz);
    setbufvalue(L, L->top, b);
    api_incr_top(L);
    return b->data;
}

static const char* aux_upvalue(StkId fi, int n, TValue** val)
{
    Closure* f;
    if (!ttisfunction(fi))
        return NULL;
    f = clvalue(fi);
    if (f->isC)
    {
        if (!(1 <= n && n <= f->nupvalues))
            return NULL;
        *val = &f->c.upvals[n - 1];
        return "";
    }
    else
    {
        Proto* p = f->l.p;
        if (!(1 <= n && n <= p->nups)) // not a valid upvalue
            return NULL;
        TValue* r = &f->l.uprefs[n - 1];
        *val = ttisupval(r) ? upvalue(r)->v : r;
        if (!(1 <= n && n <= p->sizeupvalues)) // don't have a name for this upvalue
            return "";
        return getstr(p->upvalues[n - 1]);
    }
}

const char* lua_getupvalue(lua_State* L, int funcindex, int n)
{
    luaC_threadbarrier(L);
    TValue* val;
    const char* name = aux_upvalue(index2addr(L, funcindex), n, &val);
    if (name)
    {
        setobj2s(L, L->top, val);
        api_incr_top(L);
    }
    return name;
}

const char* lua_setupvalue(lua_State* L, int funcindex, int n)
{
    api_checknelems(L, 1);
    StkId fi = index2addr(L, funcindex);
    TValue* val;
    const char* name = aux_upvalue(fi, n, &val);
    if (name)
    {
        L->top--;
        setobj(L, val, L->top);
        luaC_barrier(L, clvalue(fi), L->top);
    }
    return name;
}

uintptr_t lua_encodepointer(lua_State* L, uintptr_t p)
{
    global_State* g = L->global;
    return uintptr_t((g->ptrenckey[0] * p + g->ptrenckey[2]) ^ (g->ptrenckey[1] * p + g->ptrenckey[3]));
}

int lua_ref(lua_State* L, int idx)
{
    api_check(L, idx != LUA_REGISTRYINDEX); // idx is a stack index for value
    int ref = LUA_REFNIL;
    global_State* g = L->global;
    StkId p = index2addr(L, idx);
    if (!ttisnil(p))
    {
        LuaTable* reg = hvalue(registry(L));

        if (g->registryfree != 0)
        { // reuse existing slot
            ref = g->registryfree;
        }
        else
        { // no free elements
            ref = luaH_getn(reg);
            ref++; // create new reference
        }

        TValue* slot = luaH_setnum(L, reg, ref);
        if (g->registryfree != 0)
            g->registryfree = int(nvalue(slot));
        setobj2t(L, slot, p);
        luaC_barriert(L, reg, p);
    }
    return ref;
}

void lua_unref(lua_State* L, int ref)
{
    if (ref <= LUA_REFNIL)
        return;

    global_State* g = L->global;
    LuaTable* reg = hvalue(registry(L));

    const TValue* slot = luaH_getnum(reg, ref);
    api_check(L, slot != luaO_nilobject);

    // similar to how 'luaH_setnum' makes non-nil slot value mutable
    TValue* mutableSlot = (TValue*)slot;

    // NB: no barrier needed because value isn't collectable
    setnvalue(mutableSlot, g->registryfree);

    g->registryfree = ref;
}

void lua_setuserdatatag(lua_State* L, int idx, int tag)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT);
    StkId o = index2addr(L, idx);
    api_check(L, ttisuserdata(o));
    uvalue(o)->tag = uint8_t(tag);
}

void lua_setuserdatadtor(lua_State* L, int tag, lua_Destructor dtor)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT);
    L->global->udatagc[tag] = dtor;
}

lua_Destructor lua_getuserdatadtor(lua_State* L, int tag)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT);
    return L->global->udatagc[tag];
}

void lua_setuserdatametatable(lua_State* L, int tag)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT);
    api_check(L, !L->global->udatamt[tag]); // reassignment not supported
    api_check(L, ttistable(L->top - 1));
    L->global->udatamt[tag] = hvalue(L->top - 1);
    L->top--;
}

void lua_getuserdatametatable(lua_State* L, int tag)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT);
    luaC_threadbarrier(L);

    if (LuaTable* h = L->global->udatamt[tag])
    {
        sethvalue(L, L->top, h);
    }
    else
    {
        setnilvalue(L->top);
    }

    api_incr_top(L);
}

int LUA_API lua_registeruserdatadirectaccess(
    lua_State* L,
    int tag,
    lua_UserdataDirectAccess get,
    lua_UserdataDirectAccess set,
    lua_UserdataDirectNamecall namecall
)
{
    api_check(L, unsigned(tag) < LUA_UTAG_LIMIT);
    luaC_threadbarrier(L);

    if (LuaTable* h = L->global->udatamt[tag])
    {
        // only metamehtods that are present will be called directly
        lua_UdataDirectAccessData& udatadirect = L->global->udatadirect[tag];

        if (const TValue* indextm = fasttm(L, h, TM_INDEX))
        {
            udatadirect.indextm = *indextm;
            udatadirect.index = get;
        }

        if (const TValue* newindextm = fasttm(L, h, TM_NEWINDEX))
        {
            udatadirect.newindextm = *newindextm;
            udatadirect.newindex = set;
        }

        if (const TValue* namecalltm = fasttm(L, h, TM_NAMECALL))
        {
            udatadirect.namecalltm = *namecalltm;
            udatadirect.namecall = namecall;
        }

        return 1;
    }

    return 0;
}

void lua_setlightuserdataname(lua_State* L, int tag, const char* name)
{
    api_check(L, unsigned(tag) < LUA_LUTAG_LIMIT);
    api_check(L, !L->global->lightuserdataname[tag]); // renaming not supported
    if (!L->global->lightuserdataname[tag])
    {
        L->global->lightuserdataname[tag] = luaS_new(L, name);
        luaS_fix(L->global->lightuserdataname[tag]); // never collect these names
    }
}

const char* lua_getlightuserdataname(lua_State* L, int tag)
{
    api_check(L, unsigned(tag) < LUA_LUTAG_LIMIT);
    const TString* name = L->global->lightuserdataname[tag];
    return name ? getstr(name) : nullptr;
}

void lua_clonefunction(lua_State* L, int idx)
{
    luaC_checkGC(L);
    luaC_threadbarrier(L);
    StkId p = index2addr(L, idx);
    api_check(L, isLfunction(p));
    Closure* cl = clvalue(p);
    Closure* newcl = luaF_newLclosure(L, cl->nupvalues, L->gt, cl->l.p);
    for (int i = 0; i < cl->nupvalues; ++i)
        setobj2n(L, &newcl->l.uprefs[i], &cl->l.uprefs[i]);
    setclvalue(L, L->top, newcl);
    api_incr_top(L);
}

void lua_cleartable(lua_State* L, int idx)
{
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));
    LuaTable* tt = hvalue(t);
    if (tt->readonly)
        luaG_readonlyerror(L);
    luaH_clear(tt);
}

void lua_clonetable(lua_State* L, int idx)
{
    StkId t = index2addr(L, idx);
    api_check(L, ttistable(t));

    LuaTable* tt = luaH_clone(L, hvalue(t));
    sethvalue(L, L->top, tt);
    api_incr_top(L);
}

lua_Callbacks* lua_callbacks(lua_State* L)
{
    return &L->global->cb;
}

void lua_setmemcat(lua_State* L, int category)
{
    api_check(L, unsigned(category) < LUA_MEMORY_CATEGORIES);
    L->activememcat = uint8_t(category);
}

size_t lua_totalbytes(lua_State* L, int category)
{
    api_check(L, category < LUA_MEMORY_CATEGORIES);
    return category < 0 ? L->global->totalbytes : L->global->memcatbytes[category];
}

lua_Alloc lua_getallocf(lua_State* L, void** ud)
{
    lua_Alloc f = L->global->frealloc;
    if (ud)
        *ud = L->global->ud;
    return f;
}
