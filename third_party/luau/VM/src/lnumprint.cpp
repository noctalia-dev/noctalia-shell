// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
// This code is based on Lua 5.x implementation licensed under MIT License; see lua_LICENSE.txt for details
#include "luaconf.h"
#include "lnumutils.h"

#include "lcommon.h"

#include <string.h>

#ifdef _MSC_VER
#include <intrin.h>
#endif

// This work is based on:
// Raffaello Giulietti. The Schubfach way to render doubles. 2021
// https://drive.google.com/file/d/1IEeATSVnEE6TkrHlCYNY2GjaraBjOT4f/edit

// The code uses the notation from the paper for local variables where appropriate, and refers to paper sections/figures/results.

// 9.8.2. Precomputed table for 128-bit overestimates of powers of 10 (see figure 3 for table bounds)
// To avoid storing 616 128-bit numbers directly we use a technique inspired by Dragonbox implementation and store 16 consecutive
// powers using a 128-bit baseline and a bitvector with 1-bit scale and 3-bit offset for the delta between each entry and base*5^k
static const int kPow10TableMin = -292;
static const int kPow10TableMax = 324;

// clang-format off
static const uint64_t kPow5Table[16] = {
    0x8000000000000000, 0xa000000000000000, 0xc800000000000000, 0xfa00000000000000, 0x9c40000000000000, 0xc350000000000000,
    0xf424000000000000, 0x9896800000000000, 0xbebc200000000000, 0xee6b280000000000, 0x9502f90000000000, 0xba43b74000000000,
    0xe8d4a51000000000, 0x9184e72a00000000, 0xb5e620f480000000, 0xe35fa931a0000000,
};
static const uint64_t kPow10Table[(kPow10TableMax - kPow10TableMin + 1 + 15) / 16][3] = {
    {0xff77b1fcbebcdc4f, 0x25e8e89c13bb0f7b, 0x333443443333443b}, {0x8dd01fad907ffc3b, 0xae3da7d97f6792e4, 0xbbb3ab3cb3ba3cbc},
    {0x9d71ac8fada6c9b5, 0x6f773fc3603db4aa, 0x4ba4bc4bb4bb4bcc}, {0xaecc49914078536d, 0x58fae9f773886e19, 0x3ba3bc33b43b43bb},
    {0xc21094364dfb5636, 0x985915fc12f542e5, 0x33b43b43a33b33cb}, {0xd77485cb25823ac7, 0x7d633293366b828c, 0x34b44c444343443c},
    {0xef340a98172aace4, 0x86fb897116c87c35, 0x333343333343334b}, {0x84c8d4dfd2c63f3b, 0x29ecd9f40041e074, 0xccaccbbcbcbb4bbc},
    {0x936b9fcebb25c995, 0xcab10dd900beec35, 0x3ab3ab3ab3bb3bbb}, {0xa3ab66580d5fdaf5, 0xc13e60d0d2e0ebbb, 0x4cc3dc4db4db4dbb},
    {0xb5b5ada8aaff80b8, 0x0d819992132456bb, 0x33b33a34c33b34ab}, {0xc9bcff6034c13052, 0xfc89b393dd02f0b6, 0x33c33b44b43c34bc},
    {0xdff9772470297ebd, 0x59787e2b93bc56f8, 0x43b444444443434c}, {0xf8a95fcf88747d94, 0x75a44c6397ce912b, 0x443334343443343b},
    {0x8a08f0f8bf0f156b, 0x1b8e9ecb641b5900, 0xbbabab3aa3ab4ccc}, {0x993fe2c6d07b7fab, 0xe546a8038efe402a, 0x4cb4bc4db4db4bcc},
    {0xaa242499697392d2, 0xdde50bd1d5d0b9ea, 0x3ba3ba3bb33b33bc}, {0xbce5086492111aea, 0x88f4bb1ca6bcf585, 0x44b44c44c44c43cb},
    {0xd1b71758e219652b, 0xd3c36113404ea4a9, 0x44c44c44c444443b}, {0xe8d4a51000000000, 0x0000000000000000, 0x444444444444444c},
    {0x813f3978f8940984, 0x4000000000000000, 0xcccccccccccccccc}, {0x8f7e32ce7bea5c6f, 0xe4820023a2000000, 0xbba3bc4cc4cc4ccc},
    {0x9f4f2726179a2245, 0x01d762422c946591, 0x4aa3bb3aa3ba3bab}, {0xb0de65388cc8ada8, 0x3b25a55f43294bcc, 0x3ca33b33b44b43bc},
    {0xc45d1df942711d9a, 0x3ba5d0bd324f8395, 0x44c44c34c44b44cb}, {0xda01ee641a708de9, 0xe80e6f4820cc9496, 0x33b33b343333333c},
    {0xf209787bb47d6b84, 0xc0678c5dbd23a49b, 0x443444444443443b}, {0x865b86925b9bc5c2, 0x0b8a2392ba45a9b3, 0xdbccbcccb4cb3bbb},
    {0x952ab45cfa97a0b2, 0xdd945a747bf26184, 0x3bc4bb4ab3ca3cbc}, {0xa59bc234db398c25, 0x43fab9837e699096, 0x3bb3ac3ab3bb33ac},
    {0xb7dcbf5354e9bece, 0x0c11ed6d538aeb30, 0x33b43b43b34c34dc}, {0xcc20ce9bd35c78a5, 0x31ec038df7b441f5, 0x34c44c43c44b44cb},
    {0xe2a0b5dc971f303a, 0x2e44ae64840fd61e, 0x333333333333333c}, {0xfb9b7cd9a4a7443c, 0x169840ef017da3b2, 0x433344443333344c},
    {0x8bab8eefb6409c1a, 0x1ad089b6c2f7548f, 0xdcbdcc3cc4cc4bcb}, {0x9b10a4e5e9913128, 0xca7cf2b4191c8327, 0x3ab3cb3bc3bb4bbb},
    {0xac2820d9623bf429, 0x546345fa9fbdcd45, 0x3bb3cc43c43c43cb}, {0xbf21e44003acdd2c, 0xe0470a63e6bd56c4, 0x44b34a43b44c44bc},
    {0xd433179d9c8cb841, 0x5fa60692a46151ec, 0x43a33a33a333333c},
};
// clang-format on

static const char kDigitTable[] = "0001020304050607080910111213141516171819202122232425262728293031323334353637383940414243444546474849"
                                  "5051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899";

// x*y => 128-bit product (lo+hi)
inline uint64_t mul128(uint64_t x, uint64_t y, uint64_t* hi)
{
#if defined(_MSC_VER) && defined(_M_X64)
    return _umul128(x, y, hi);
#elif defined(__SIZEOF_INT128__)
    unsigned __int128 r = x;
    r *= y;
    *hi = uint64_t(r >> 64);
    return uint64_t(r);
#else
    uint32_t x0 = uint32_t(x), x1 = uint32_t(x >> 32);
    uint32_t y0 = uint32_t(y), y1 = uint32_t(y >> 32);
    uint64_t p11 = uint64_t(x1) * y1, p01 = uint64_t(x0) * y1;
    uint64_t p10 = uint64_t(x1) * y0, p00 = uint64_t(x0) * y0;
    uint64_t mid = p10 + (p00 >> 32) + uint32_t(p01);
    uint64_t r0 = (mid << 32) | uint32_t(p00);
    uint64_t r1 = p11 + (mid >> 32) + (p01 >> 32);
    *hi = r1;
    return r0;
#endif
}

// (x*y)>>64 => 128-bit product (lo+hi)
inline uint64_t mul192hi(uint64_t xhi, uint64_t xlo, uint64_t y, uint64_t* hi)
{
    uint64_t z2;
    uint64_t z1 = mul128(xhi, y, &z2);

    uint64_t z1c;
    uint64_t z0 = mul128(xlo, y, &z1c);
    (void)z0;

    z1 += z1c;
    z2 += (z1 < z1c);

    *hi = z2;
    return z1;
}

// 9.3. Rounding to odd (+ figure 8 + result 23)
inline uint64_t roundodd(uint64_t ghi, uint64_t glo, uint64_t cp)
{
    uint64_t xhi;
    uint64_t xlo = mul128(glo, cp, &xhi);
    (void)xlo;

    uint64_t yhi;
    uint64_t ylo = mul128(ghi, cp, &yhi);

    uint64_t z = ylo + xhi;
    return (yhi + (z < xhi)) | (z > 1);
}

struct Decimal
{
    uint64_t s;
    int k;
};

static Decimal schubfach(int exponent, uint64_t fraction)
{
    // Extract c & q such that c*2^q == |v|
    uint64_t c = fraction;
    int q = exponent - 1023 - 51;

    if (exponent != 0) // normal numbers have implicit leading 1
    {
        c |= (1ull << 52);
        q--;
    }

    // 8.3. Fast path for integers
    if (unsigned(-q) < 53 && (c & ((1ull << (-q)) - 1)) == 0)
        return {c >> (-q), 0};

    // 5. Rounding interval
    int irr = (c == (1ull << 52) && q != -1074); // Qmin
    int out = int(c & 1);

    // 9.8.1. Boundaries for c
    uint64_t cbl = 4 * c - 2 + irr;
    uint64_t cb = 4 * c;
    uint64_t cbr = 4 * c + 2;

    // 9.1. Computing k and h
    const int Q = 20;
    const int C = 315652;   // floor(2^Q * log10(2))
    const int A = -131008;  // floor(2^Q * log10(3/4))
    const int C2 = 3483294; // floor(2^Q * log2(10))
    int k = (q * C + (irr ? A : 0)) >> Q;
    int h = q + ((-k * C2) >> Q) + 1; // see (9) in 9.9

    // 9.8.2. Overestimates of powers of 10
    // Recover 10^-k fraction using compact tables generated by tools/numutils.py
    // The 128-bit fraction is encoded as 128-bit baseline * power-of-5 * scale + offset
    LUAU_ASSERT(-k >= kPow10TableMin && -k <= kPow10TableMax);
    int gtoff = -k - kPow10TableMin;
    const uint64_t* gt = kPow10Table[gtoff >> 4];

    uint64_t ghi;
    uint64_t glo = mul192hi(gt[0], gt[1], kPow5Table[gtoff & 15], &ghi);

    // Apply 1-bit scale + 3-bit offset; note, offset is intentionally applied without carry, numutils.py validates that this is sufficient
    int gterr = (gt[2] >> ((gtoff & 15) * 4)) & 15;
    int gtscale = gterr >> 3;

    ghi <<= gtscale;
    ghi += (glo >> 63) & gtscale;
    glo <<= gtscale;
    glo -= (gterr & 7) - 4;

    // 9.9. Boundaries for v
    uint64_t vbl = roundodd(ghi, glo, cbl << h);
    uint64_t vb = roundodd(ghi, glo, cb << h);
    uint64_t vbr = roundodd(ghi, glo, cbr << h);

    // Main algorithm; see figure 7 + figure 9
    uint64_t s = vb / 4;

    if (s >= 10)
    {
        uint64_t sp = s / 10;

        bool upin = vbl + out <= 40 * sp;
        bool wpin = vbr >= 40 * sp + 40 + out;

        if (upin != wpin)
            return {sp + wpin, k + 1};
    }

    // Figure 7 contains the algorithm to select between u (s) and w (s+1)
    // rup computes the last 4 conditions in that algorithm
    // rup is only used when uin == win, but since these branches predict poorly we use branchless selects
    bool uin = vbl + out <= 4 * s;
    bool win = 4 * s + 4 + out <= vbr;
    bool rup = vb >= 4 * s + 2 + 1 - (s & 1);

    return {s + (uin != win ? win : rup), k};
}

static char* printspecial(char* buf, int sign, uint64_t fraction)
{
    if (fraction == 0)
    {
        memcpy(buf, ("-inf") + (1 - sign), 4);
        return buf + 3 + sign;
    }
    else
    {
        memcpy(buf, "nan", 4);
        return buf + 3;
    }
}

static char* printunsignedrev(char* end, uint64_t num)
{
    while (num >= 10000)
    {
        unsigned int tail = unsigned(num % 10000);

        memcpy(end - 4, &kDigitTable[int(tail / 100) * 2], 2);
        memcpy(end - 2, &kDigitTable[int(tail % 100) * 2], 2);
        num /= 10000;
        end -= 4;
    }

    unsigned int rest = unsigned(num);

    while (rest >= 10)
    {
        memcpy(end - 2, &kDigitTable[int(rest % 100) * 2], 2);
        rest /= 100;
        end -= 2;
    }

    if (rest)
    {
        end[-1] = '0' + int(rest);
        end -= 1;
    }

    return end;
}

static char* printexp(char* buf, int num)
{
    *buf++ = 'e';
    *buf++ = num < 0 ? '-' : '+';

    int v = num < 0 ? -num : num;

    if (v >= 100)
    {
        *buf++ = '0' + (v / 100);
        v %= 100;
    }

    memcpy(buf, &kDigitTable[v * 2], 2);
    return buf + 2;
}

inline char* trimzero(char* end)
{
    while (end[-1] == '0')
        end--;

    return end;
}

// We use fixed-length memcpy/memset since they lower to fast SIMD+scalar writes; the target buffers should have padding space
#define fastmemcpy(dst, src, size, sizefast) check_exp((size) <= sizefast, memcpy(dst, src, sizefast))
#define fastmemset(dst, val, size, sizefast) check_exp((size) <= sizefast, memset(dst, val, sizefast))

char* luai_num2str(char* buf, double n)
{
    // IEEE-754
    union
    {
        double v;
        uint64_t bits;
    } v = {n};
    int sign = int(v.bits >> 63);
    int exponent = int(v.bits >> 52) & 2047;
    uint64_t fraction = v.bits & ((1ull << 52) - 1);

    // specials
    if (LUAU_UNLIKELY(exponent == 0x7ff))
        return printspecial(buf, sign, fraction);

    // sign bit
    *buf = '-';
    buf += sign;

    // zero
    if (exponent == 0 && fraction == 0)
    {
        buf[0] = '0';
        return buf + 1;
    }

    // convert binary to decimal using Schubfach
    Decimal d = schubfach(exponent, fraction);
    LUAU_ASSERT(d.s < uint64_t(1e17));

    // print the decimal to a temporary buffer; we'll need to insert the decimal point and figure out the format
    char decbuf[40];
    char* decend = decbuf + 20; // significand needs at most 17 digits; the rest of the buffer may be copied using fixed length memcpy
    char* dec = printunsignedrev(decend, d.s);

    int declen = int(decend - dec);
    LUAU_ASSERT(declen <= 17);

    int dot = declen + d.k;

    // the limits are somewhat arbitrary but changing them may require changing fastmemset/fastmemcpy sizes below
    if (dot >= -5 && dot <= 21)
    {
        // fixed point format
        if (dot <= 0)
        {
            buf[0] = '0';
            buf[1] = '.';

            fastmemset(buf + 2, '0', -dot, 5);
            fastmemcpy(buf + 2 + (-dot), dec, declen, 17);

            return trimzero(buf + 2 + (-dot) + declen);
        }
        else if (dot == declen)
        {
            // no dot
            fastmemcpy(buf, dec, dot, 17);

            return buf + dot;
        }
        else if (dot < declen)
        {
            // dot in the middle
            fastmemcpy(buf, dec, dot, 16);

            buf[dot] = '.';

            fastmemcpy(buf + dot + 1, dec + dot, declen - dot, 16);

            return trimzero(buf + declen + 1);
        }
        else
        {
            // no dot, zero padding
            fastmemcpy(buf, dec, declen, 17);
            fastmemset(buf + declen, '0', dot - declen, 8);

            return buf + dot;
        }
    }
    else
    {
        // scientific format
        buf[0] = dec[0];
        buf[1] = '.';
        fastmemcpy(buf + 2, dec + 1, declen - 1, 16);

        char* exp = trimzero(buf + declen + 1);

        if (exp[-1] == '.')
            exp--;

        return printexp(exp, dot - 1);
    }
}

char* luai_int2str(char* buf, int64_t l)
{
    uint64_t val = (l < 0) ? ~(uint64_t)l + 1 : (uint64_t)l;

    int numDigits = 1;
    for (uint64_t cap = 10; (numDigits < 19) && (cap <= val); cap *= 10)
        numDigits++;

    int pos = (l < 0) ? numDigits : (numDigits - 1);
    buf[pos + 1] = 0;
    do
    {
        buf[pos--] = '0' + (val % 10);
        val /= 10;
    } while (val != 0);

    if (l < 0)
        buf[pos--] = '-';

    LUAU_ASSERT(pos == -1);

    return &buf[(l < 0) ? (numDigits + 1) : numDigits];
}
