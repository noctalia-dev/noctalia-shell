// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "lualib.h"

#include "lstate.h"

#include <limits>
#include <math.h>
#include <time.h>

#define LUAU_PI (3.14159265358979323846)
#define RADIANS_PER_DEGREE (LUAU_PI / 180.0)

#define LUAU_NAN (std::numeric_limits<double>::quiet_NaN())
#define LUAU_E (2.71828182845904523536)
#define LUAU_PHI (1.61803398874989484820)
#define LUAU_SQRT2 (1.41421356237309504880)
#define LUAU_TAU (6.28318530717958647692)

#define PCG32_INC 105

LUAU_FASTFLAGVARIABLE(LuauNewMathConstantsRuntime)
LUAU_FASTFLAGVARIABLE(FixMathNoisePrecision)

static uint32_t pcg32_random(uint64_t* state)
{
    uint64_t oldstate = *state;
    *state = oldstate * 6364136223846793005ULL + (PCG32_INC | 1);
    uint32_t xorshifted = uint32_t(((oldstate >> 18u) ^ oldstate) >> 27u);
    uint32_t rot = uint32_t(oldstate >> 59u);
    return (xorshifted >> rot) | (xorshifted << ((-int32_t(rot)) & 31));
}

static void pcg32_seed(uint64_t* state, uint64_t seed)
{
    *state = 0;
    pcg32_random(state);
    *state += seed;
    pcg32_random(state);
}

static int math_abs(lua_State* L)
{
    lua_pushnumber(L, fabs(luaL_checknumber(L, 1)));
    return 1;
}

static int math_sin(lua_State* L)
{
    lua_pushnumber(L, sin(luaL_checknumber(L, 1)));
    return 1;
}

static int math_sinh(lua_State* L)
{
    lua_pushnumber(L, sinh(luaL_checknumber(L, 1)));
    return 1;
}

static int math_cos(lua_State* L)
{
    lua_pushnumber(L, cos(luaL_checknumber(L, 1)));
    return 1;
}

static int math_cosh(lua_State* L)
{
    lua_pushnumber(L, cosh(luaL_checknumber(L, 1)));
    return 1;
}

static int math_tan(lua_State* L)
{
    lua_pushnumber(L, tan(luaL_checknumber(L, 1)));
    return 1;
}

static int math_tanh(lua_State* L)
{
    lua_pushnumber(L, tanh(luaL_checknumber(L, 1)));
    return 1;
}

static int math_asin(lua_State* L)
{
    lua_pushnumber(L, asin(luaL_checknumber(L, 1)));
    return 1;
}

static int math_acos(lua_State* L)
{
    lua_pushnumber(L, acos(luaL_checknumber(L, 1)));
    return 1;
}

static int math_atan(lua_State* L)
{
    lua_pushnumber(L, atan(luaL_checknumber(L, 1)));
    return 1;
}

static int math_atan2(lua_State* L)
{
    lua_pushnumber(L, atan2(luaL_checknumber(L, 1), luaL_checknumber(L, 2)));
    return 1;
}

static int math_ceil(lua_State* L)
{
    lua_pushnumber(L, ceil(luaL_checknumber(L, 1)));
    return 1;
}

static int math_floor(lua_State* L)
{
    lua_pushnumber(L, floor(luaL_checknumber(L, 1)));
    return 1;
}

static int math_fmod(lua_State* L)
{
    lua_pushnumber(L, fmod(luaL_checknumber(L, 1), luaL_checknumber(L, 2)));
    return 1;
}

static int math_modf(lua_State* L)
{
    double ip;
    double fp = modf(luaL_checknumber(L, 1), &ip);
    lua_pushnumber(L, ip);
    lua_pushnumber(L, fp);
    return 2;
}

static int math_sqrt(lua_State* L)
{
    lua_pushnumber(L, sqrt(luaL_checknumber(L, 1)));
    return 1;
}

static int math_pow(lua_State* L)
{
    lua_pushnumber(L, pow(luaL_checknumber(L, 1), luaL_checknumber(L, 2)));
    return 1;
}

static int math_log(lua_State* L)
{
    double x = luaL_checknumber(L, 1);
    double res;
    if (lua_isnoneornil(L, 2))
        res = log(x);
    else
    {
        double base = luaL_checknumber(L, 2);
        if (base == 2.0)
            res = log2(x);
        else if (base == 10.0)
            res = log10(x);
        else
            res = log(x) / log(base);
    }
    lua_pushnumber(L, res);
    return 1;
}

static int math_log10(lua_State* L)
{
    lua_pushnumber(L, log10(luaL_checknumber(L, 1)));
    return 1;
}

static int math_exp(lua_State* L)
{
    lua_pushnumber(L, exp(luaL_checknumber(L, 1)));
    return 1;
}

static int math_deg(lua_State* L)
{
    lua_pushnumber(L, luaL_checknumber(L, 1) / RADIANS_PER_DEGREE);
    return 1;
}

static int math_rad(lua_State* L)
{
    lua_pushnumber(L, luaL_checknumber(L, 1) * RADIANS_PER_DEGREE);
    return 1;
}

static int math_frexp(lua_State* L)
{
    int e;
    lua_pushnumber(L, frexp(luaL_checknumber(L, 1), &e));
    lua_pushinteger(L, e);
    return 2;
}

static int math_ldexp(lua_State* L)
{
    lua_pushnumber(L, ldexp(luaL_checknumber(L, 1), luaL_checkinteger(L, 2)));
    return 1;
}

static int math_min(lua_State* L)
{
    int n = lua_gettop(L); // number of arguments
    double dmin = luaL_checknumber(L, 1);
    int i;
    for (i = 2; i <= n; i++)
    {
        double d = luaL_checknumber(L, i);
        if (d < dmin)
            dmin = d;
    }
    lua_pushnumber(L, dmin);
    return 1;
}

static int math_max(lua_State* L)
{
    int n = lua_gettop(L); // number of arguments
    double dmax = luaL_checknumber(L, 1);
    int i;
    for (i = 2; i <= n; i++)
    {
        double d = luaL_checknumber(L, i);
        if (d > dmax)
            dmax = d;
    }
    lua_pushnumber(L, dmax);
    return 1;
}

static int math_random(lua_State* L)
{
    global_State* g = L->global;
    switch (lua_gettop(L))
    { // check number of arguments
    case 0:
    { // no arguments
        // Using ldexp instead of division for speed & clarity.
        // See http://mumble.net/~campbell/tmp/random_real.c for details on generating doubles from integer ranges.
        uint32_t rl = pcg32_random(&g->rngstate);
        uint32_t rh = pcg32_random(&g->rngstate);
        double rd = ldexp(double(rl | (uint64_t(rh) << 32)), -64);
        lua_pushnumber(L, rd); // number between 0 and 1
        break;
    }
    case 1:
    { // only upper limit
        int u = luaL_checkinteger(L, 1);
        luaL_argcheck(L, 1 <= u, 1, "interval is empty");

        uint64_t x = uint64_t(u) * pcg32_random(&g->rngstate);
        int r = int(1 + (x >> 32));
        lua_pushinteger(L, r); // int between 1 and `u'
        break;
    }
    case 2:
    { // lower and upper limits
        int l = luaL_checkinteger(L, 1);
        int u = luaL_checkinteger(L, 2);
        luaL_argcheck(L, l <= u, 2, "interval is empty");

        uint32_t ul = uint32_t(u) - uint32_t(l);
        luaL_argcheck(L, ul < UINT_MAX, 2, "interval is too large"); // -INT_MIN..INT_MAX interval can result in integer overflow
        uint64_t x = uint64_t(ul + 1) * pcg32_random(&g->rngstate);
        int r = int(l + (x >> 32));
        lua_pushinteger(L, r); // int between `l' and `u'
        break;
    }
    default:
        luaL_error(L, "wrong number of arguments");
    }
    return 1;
}

static int math_randomseed(lua_State* L)
{
    int seed = luaL_checkinteger(L, 1);

    pcg32_seed(&L->global->rngstate, seed);
    return 0;
}

static const unsigned char kPerlinHash[257] = {
    151, 160, 137, 91,  90,  15,  131, 13,  201, 95,  96,  53,  194, 233, 7,   225, 140, 36,  103, 30,  69,  142, 8,   99,  37,  240, 21,  10,  23,
    190, 6,   148, 247, 120, 234, 75,  0,   26,  197, 62,  94,  252, 219, 203, 117, 35,  11,  32,  57,  177, 33,  88,  237, 149, 56,  87,  174, 20,
    125, 136, 171, 168, 68,  175, 74,  165, 71,  134, 139, 48,  27,  166, 77,  146, 158, 231, 83,  111, 229, 122, 60,  211, 133, 230, 220, 105, 92,
    41,  55,  46,  245, 40,  244, 102, 143, 54,  65,  25,  63,  161, 1,   216, 80,  73,  209, 76,  132, 187, 208, 89,  18,  169, 200, 196, 135, 130,
    116, 188, 159, 86,  164, 100, 109, 198, 173, 186, 3,   64,  52,  217, 226, 250, 124, 123, 5,   202, 38,  147, 118, 126, 255, 82,  85,  212, 207,
    206, 59,  227, 47,  16,  58,  17,  182, 189, 28,  42,  223, 183, 170, 213, 119, 248, 152, 2,   44,  154, 163, 70,  221, 153, 101, 155, 167, 43,
    172, 9,   129, 22,  39,  253, 19,  98,  108, 110, 79,  113, 224, 232, 178, 185, 112, 104, 218, 246, 97,  228, 251, 34,  242, 193, 238, 210, 144,
    12,  191, 179, 162, 241, 81,  51,  145, 235, 249, 14,  239, 107, 49,  192, 214, 31,  181, 199, 106, 157, 184, 84,  204, 176, 115, 121, 50,  45,
    127, 4,   150, 254, 138, 236, 205, 93,  222, 114, 67,  29,  24,  72,  243, 141, 128, 195, 78,  66,  215, 61,  156, 180, 151
};

const float kPerlinGrad[16][3] = {
    {1, 1, 0},
    {-1, 1, 0},
    {1, -1, 0},
    {-1, -1, 0},
    {1, 0, 1},
    {-1, 0, 1},
    {1, 0, -1},
    {-1, 0, -1},
    {0, 1, 1},
    {0, -1, 1},
    {0, 1, -1},
    {0, -1, -1},
    {1, 1, 0},
    {0, -1, 1},
    {-1, 1, 0},
    {0, -1, -1}
};

inline float perlin_fade(float t)
{
    return t * t * t * (t * (t * 6 - 15) + 10);
}

inline float perlin_lerp(float t, float a, float b)
{
    return a + t * (b - a);
}

inline float perlin_grad(int hash, float x, float y, float z)
{
    const float* g = kPerlinGrad[hash & 15];
    return g[0] * x + g[1] * y + g[2] * z;
}

static float perlin(float x, float y, float z)
{
    float xflr = floorf(x);
    float yflr = floorf(y);
    float zflr = floorf(z);

    int xi = int(xflr) & 255;
    int yi = int(yflr) & 255;
    int zi = int(zflr) & 255;

    float xf = x - xflr;
    float yf = y - yflr;
    float zf = z - zflr;

    float u = perlin_fade(xf);
    float v = perlin_fade(yf);
    float w = perlin_fade(zf);

    const unsigned char* p = kPerlinHash;

    int a = (p[xi] + yi) & 255;
    int aa = (p[a] + zi) & 255;
    int ab = (p[a + 1] + zi) & 255;

    int b = (p[xi + 1] + yi) & 255;
    int ba = (p[b] + zi) & 255;
    int bb = (p[b + 1] + zi) & 255;

    float la = perlin_lerp(u, perlin_grad(p[aa], xf, yf, zf), perlin_grad(p[ba], xf - 1, yf, zf));
    float lb = perlin_lerp(u, perlin_grad(p[ab], xf, yf - 1, zf), perlin_grad(p[bb], xf - 1, yf - 1, zf));
    float la1 = perlin_lerp(u, perlin_grad(p[aa + 1], xf, yf, zf - 1), perlin_grad(p[ba + 1], xf - 1, yf, zf - 1));
    float lb1 = perlin_lerp(u, perlin_grad(p[ab + 1], xf, yf - 1, zf - 1), perlin_grad(p[bb + 1], xf - 1, yf - 1, zf - 1));

    return perlin_lerp(w, perlin_lerp(v, la, lb), perlin_lerp(v, la1, lb1));
}

static int math_noise(lua_State* L)
{
    int nx, ny, nz;
    double x = lua_tonumberx(L, 1, &nx);
    double y = lua_tonumberx(L, 2, &ny);
    double z = lua_tonumberx(L, 3, &nz);

    luaL_argexpected(L, nx, 1, "number");
    luaL_argexpected(L, ny || lua_isnoneornil(L, 2), 2, "number");
    luaL_argexpected(L, nz || lua_isnoneornil(L, 3), 3, "number");

    if (FFlag::FixMathNoisePrecision)
    {
        // NOTES: input numbers from Luau are double with higher precision and range than float used by perlin().
        // If we don't do this, for large numbers, perlin() will return almost always 0, since with larger inputs,
        // most of the mantissa is used to store the integer part and perlin() is always 0 at integer cell values.
        // Noise repeat exactly every 256 units in all dimensions, so we can wrap to prevent loss of precision for large numbers.
        x = fmod(x, 256.0);
        y = fmod(y, 256.0);
        z = fmod(z, 256.0);
    }

    double r = perlin((float)x, (float)y, (float)z);

    lua_pushnumber(L, r);
    return 1;
}

static int math_clamp(lua_State* L)
{
    double v = luaL_checknumber(L, 1);
    double min = luaL_checknumber(L, 2);
    double max = luaL_checknumber(L, 3);

    luaL_argcheck(L, min <= max, 3, "max must be greater than or equal to min");

    double r = v < min ? min : v;
    r = r > max ? max : r;

    lua_pushnumber(L, r);
    return 1;
}

static int math_sign(lua_State* L)
{
    double v = luaL_checknumber(L, 1);
    lua_pushnumber(L, v > 0.0 ? 1.0 : v < 0.0 ? -1.0 : 0.0);
    return 1;
}

static int math_round(lua_State* L)
{
    lua_pushnumber(L, round(luaL_checknumber(L, 1)));
    return 1;
}

static int math_map(lua_State* L)
{
    double x = luaL_checknumber(L, 1);
    double inmin = luaL_checknumber(L, 2);
    double inmax = luaL_checknumber(L, 3);
    double outmin = luaL_checknumber(L, 4);
    double outmax = luaL_checknumber(L, 5);

    double result = outmin + (x - inmin) * (outmax - outmin) / (inmax - inmin);
    lua_pushnumber(L, result);
    return 1;
}

static int math_lerp(lua_State* L)
{
    double a = luaL_checknumber(L, 1);
    double b = luaL_checknumber(L, 2);
    double t = luaL_checknumber(L, 3);

    double r = (t == 1.0) ? b : a + (b - a) * t;
    lua_pushnumber(L, r);
    return 1;
}

static int math_isnan(lua_State* L)
{
    double x = luaL_checknumber(L, 1);

    lua_pushboolean(L, isnan(x));
    return 1;
}

static int math_isinf(lua_State* L)
{
    double x = luaL_checknumber(L, 1);

    lua_pushboolean(L, isinf(x));
    return 1;
}

static int math_isfinite(lua_State* L)
{
    double x = luaL_checknumber(L, 1);

    lua_pushboolean(L, isfinite(x));
    return 1;
}

static const luaL_Reg mathlib[] = {
    {"abs", math_abs},
    {"acos", math_acos},
    {"asin", math_asin},
    {"atan2", math_atan2},
    {"atan", math_atan},
    {"ceil", math_ceil},
    {"cosh", math_cosh},
    {"cos", math_cos},
    {"deg", math_deg},
    {"exp", math_exp},
    {"floor", math_floor},
    {"fmod", math_fmod},
    {"frexp", math_frexp},
    {"ldexp", math_ldexp},
    {"log10", math_log10},
    {"log", math_log},
    {"max", math_max},
    {"min", math_min},
    {"modf", math_modf},
    {"pow", math_pow},
    {"rad", math_rad},
    {"random", math_random},
    {"randomseed", math_randomseed},
    {"sinh", math_sinh},
    {"sin", math_sin},
    {"sqrt", math_sqrt},
    {"tanh", math_tanh},
    {"tan", math_tan},
    {"noise", math_noise},
    {"clamp", math_clamp},
    {"sign", math_sign},
    {"round", math_round},
    {"map", math_map},
    {"lerp", math_lerp},
    {"isnan", math_isnan},
    {"isinf", math_isinf},
    {"isfinite", math_isfinite},
    {NULL, NULL},
};

/*
** Open math library
*/
int luaopen_math(lua_State* L)
{
    uint64_t seed = lua_encodepointer(L, uintptr_t(L));
    seed ^= time(NULL);
    seed ^= clock();

    pcg32_seed(&L->global->rngstate, seed);

    luaL_register(L, LUA_MATHLIBNAME, mathlib);

    lua_pushnumber(L, LUAU_PI);
    lua_setfield(L, -2, "pi");
    lua_pushnumber(L, HUGE_VAL);
    lua_setfield(L, -2, "huge");

    if (FFlag::LuauNewMathConstantsRuntime)
    {
        lua_pushnumber(L, LUAU_NAN);
        lua_setfield(L, -2, "nan");
        lua_pushnumber(L, LUAU_E);
        lua_setfield(L, -2, "e");
        lua_pushnumber(L, LUAU_PHI);
        lua_setfield(L, -2, "phi");
        lua_pushnumber(L, LUAU_SQRT2);
        lua_setfield(L, -2, "sqrt2");
        lua_pushnumber(L, LUAU_TAU);
        lua_setfield(L, -2, "tau");
    }

    return 1;
}
