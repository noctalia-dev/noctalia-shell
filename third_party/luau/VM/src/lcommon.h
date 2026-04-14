// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#pragma once

#include <limits.h>
#include <stdint.h>

#include "luaconf.h"

#include "Luau/Common.h"

// internal assertions for in-house debugging
#define check_exp(c, e) (LUAU_ASSERT(c), (e))
#define api_check(l, e) LUAU_ASSERT(e)

#ifndef cast_to
#define cast_to(t, exp) ((t)(exp))
#endif

#define cast_byte(i) cast_to(uint8_t, (i))
#define cast_num(i) cast_to(double, (i))
#define cast_int(i) cast_to(int, (i))

/*
** type for virtual-machine instructions
** must be an unsigned with (at least) 4 bytes (see details in lopcodes.h)
*/
typedef uint32_t Instruction;

/*
** macro to control inclusion of some hard tests on stack reallocation
*/
#if defined(HARDSTACKTESTS) && HARDSTACKTESTS
#define condhardstacktests(x) (x)
#else
#define condhardstacktests(x) ((void)0)
#endif

/*
** macro to control inclusion of some hard tests on garbage collection
*/
#if defined(HARDMEMTESTS) && HARDMEMTESTS
#define condhardmemtests(x, l) (HARDMEMTESTS >= l ? (x) : (void)0)
#else
#define condhardmemtests(x, l) ((void)0)
#endif
