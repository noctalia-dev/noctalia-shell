// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lua.h"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#ifdef __APPLE__
#include <mach/mach.h>
#include <mach/mach_time.h>
#endif

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#endif

#include <time.h>

static double clock_period()
{
#if defined(_WIN32)
    LARGE_INTEGER result = {};
    QueryPerformanceFrequency(&result);
    return 1.0 / double(result.QuadPart);
#elif defined(__APPLE__)
    mach_timebase_info_data_t result = {};
    mach_timebase_info(&result);
    return double(result.numer) / double(result.denom) * 1e-9;
#elif defined(__linux__) || defined(__FreeBSD__)
    return 1e-9;
#elif defined(__EMSCRIPTEN__)
    return 1e-3;
#else
    return 1.0 / double(CLOCKS_PER_SEC);
#endif
}

static double clock_timestamp()
{
#if defined(_WIN32)
    LARGE_INTEGER result = {};
    QueryPerformanceCounter(&result);
    return double(result.QuadPart);
#elif defined(__APPLE__)
    return double(mach_absolute_time());
#elif defined(__linux__) || defined(__FreeBSD__)
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * 1e9 + now.tv_nsec;
#elif defined(__EMSCRIPTEN__)
    return emscripten_get_now();
#else
    return double(clock());
#endif
}

double lua_clock()
{
    static double period = clock_period();

    return clock_timestamp() * period;
}
