// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "Luau/StringUtils.h"

#include "Luau/Common.h"

#include <array>
#include <vector>
#include <string>
#include <string.h>
#include <stdint.h>

namespace Luau
{

void vformatAppend(std::string& ret, const char* fmt, va_list args)
{
    va_list argscopy;
    va_copy(argscopy, args);
#ifdef _MSC_VER
    int actualSize = _vscprintf(fmt, argscopy);
#else
    int actualSize = vsnprintf(NULL, 0, fmt, argscopy);
#endif
    va_end(argscopy);

    if (actualSize <= 0)
        return;

    size_t sz = ret.size();
    ret.resize(sz + actualSize);
    vsnprintf(&ret[0] + sz, actualSize + 1, fmt, args);
}

std::string format(const char* fmt, ...)
{
    std::string result;
    va_list args;
    va_start(args, fmt);
    vformatAppend(result, fmt, args);
    va_end(args);
    return result;
}

void formatAppend(std::string& str, const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vformatAppend(str, fmt, args);
    va_end(args);
}

std::string vformat(const char* fmt, va_list args)
{
    std::string ret;
    vformatAppend(ret, fmt, args);
    return ret;
}

template<typename String>
static std::string joinImpl(const std::vector<String>& segments, std::string_view delimiter)
{
    if (segments.empty())
        return "";

    size_t len = (segments.size() - 1) * delimiter.size();
    for (const auto& sv : segments)
        len += sv.size();

    std::string result;
    result.resize(len);
    char* dest = const_cast<char*>(result.data()); // This const_cast is only necessary until C++17

    auto it = segments.begin();
    memcpy(dest, it->data(), it->size());
    dest += it->size();
    ++it;
    for (; it != segments.end(); ++it)
    {
        memcpy(dest, delimiter.data(), delimiter.size());
        dest += delimiter.size();
        memcpy(dest, it->data(), it->size());
        dest += it->size();
    }

    LUAU_ASSERT(dest == result.data() + len);

    return result;
}

std::string join(const std::vector<std::string_view>& segments, std::string_view delimiter)
{
    return joinImpl(segments, delimiter);
}

std::string join(const std::vector<std::string>& segments, std::string_view delimiter)
{
    return joinImpl(segments, delimiter);
}

std::vector<std::string_view> split(std::string_view s, char delimiter)
{
    std::vector<std::string_view> result;

    while (!s.empty())
    {
        auto index = s.find(delimiter);
        if (index == std::string::npos)
        {
            result.push_back(s);
            break;
        }
        result.push_back(s.substr(0, index));
        s.remove_prefix(index + 1);
    }

    return result;
}

size_t editDistance(std::string_view a, std::string_view b)
{
    // When there are matching prefix and suffix, they end up computing as zero cost, effectively making it no-op. We drop these characters.
    while (!a.empty() && !b.empty() && a.front() == b.front())
    {
        a.remove_prefix(1);
        b.remove_prefix(1);
    }

    while (!a.empty() && !b.empty() && a.back() == b.back())
    {
        a.remove_suffix(1);
        b.remove_suffix(1);
    }

    // Since we know the edit distance is the difference of the length of A and B discounting the matching prefixes and suffixes,
    // it is therefore pointless to run the rest of this function to find that out. We immediately infer this size and return it.
    if (a.empty())
        return b.size();
    if (b.empty())
        return a.size();

    size_t maxDistance = a.size() + b.size();

    std::vector<size_t> distances((a.size() + 2) * (b.size() + 2), 0);
    auto getPos = [b](size_t x, size_t y) -> size_t
    {
        return (x * (b.size() + 2)) + y;
    };

    distances[0] = maxDistance;

    for (size_t x = 0; x <= a.size(); ++x)
    {
        distances[getPos(x + 1, 0)] = maxDistance;
        distances[getPos(x + 1, 1)] = x;
    }

    for (size_t y = 0; y <= b.size(); ++y)
    {
        distances[getPos(0, y + 1)] = maxDistance;
        distances[getPos(1, y + 1)] = y;
    }

    std::array<size_t, 256> seenCharToRow;
    seenCharToRow.fill(0);

    for (size_t x = 1; x <= a.size(); ++x)
    {
        size_t lastMatchedY = 0;

        for (size_t y = 1; y <= b.size(); ++y)
        {
            // The value of b[N] can be negative with unicode characters
            unsigned char bSeenCharIndex = static_cast<unsigned char>(b[y - 1]);
            size_t x1 = seenCharToRow[bSeenCharIndex];
            size_t y1 = lastMatchedY;

            size_t cost = 1;
            if (a[x - 1] == b[y - 1])
            {
                cost = 0;
                lastMatchedY = y;
            }

            size_t transposition = distances[getPos(x1, y1)] + (x - x1 - 1) + 1 + (y - y1 - 1);
            size_t substitution = distances[getPos(x, y)] + cost;
            size_t insertion = distances[getPos(x, y + 1)] + 1;
            size_t deletion = distances[getPos(x + 1, y)] + 1;

            // It's more performant to use std::min(size_t, size_t) rather than the initializer_list overload.
            // Until proven otherwise, please do not change this.
            distances[getPos(x + 1, y + 1)] = std::min(std::min(insertion, deletion), std::min(substitution, transposition));
        }

        // The value of a[N] can be negative with unicode characters
        unsigned char aSeenCharIndex = static_cast<unsigned char>(a[x - 1]);
        seenCharToRow[aSeenCharIndex] = x;
    }

    return distances[getPos(a.size() + 1, b.size() + 1)];
}

bool startsWith(std::string_view haystack, std::string_view needle)
{
    // ::starts_with is C++20
    return haystack.size() >= needle.size() && haystack.substr(0, needle.size()) == needle;
}

bool equalsLower(std::string_view lhs, std::string_view rhs)
{
    if (lhs.size() != rhs.size())
        return false;

    for (size_t i = 0; i < lhs.size(); ++i)
        if (tolower(uint8_t(lhs[i])) != tolower(uint8_t(rhs[i])))
            return false;

    return true;
}

size_t hashRange(const char* data, size_t size)
{
    // FNV-1a
    uint32_t hash = 2166136261;

    for (size_t i = 0; i < size; ++i)
    {
        hash ^= uint8_t(data[i]);
        hash *= 16777619;
    }

    return hash;
}

bool isIdentifier(std::string_view s)
{
    return (s.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890_") == std::string::npos);
}

std::string escape(std::string_view s, bool escapeForInterpString)
{
    std::string r;
    r.reserve(s.size() + 50); // arbitrary number to guess how many characters we'll be inserting

    for (uint8_t c : s)
    {
        if (c >= ' ' && c != '\\' && c != '\'' && c != '\"' && c != '`' && c != '{')
            r += c;
        else
        {
            r += '\\';

            if (escapeForInterpString && (c == '`' || c == '{'))
            {
                r += c;
                continue;
            }

            switch (c)
            {
            case '\a':
                r += 'a';
                break;
            case '\b':
                r += 'b';
                break;
            case '\f':
                r += 'f';
                break;
            case '\n':
                r += 'n';
                break;
            case '\r':
                r += 'r';
                break;
            case '\t':
                r += 't';
                break;
            case '\v':
                r += 'v';
                break;
            case '\'':
                r += '\'';
                break;
            case '\"':
                r += '\"';
                break;
            case '\\':
                r += '\\';
                break;
            default:
                Luau::formatAppend(r, "%03u", c);
            }
        }
    }

    return r;
}

static bool isWhitespace(char c)
{
    return c == ' ' || c == '\n' || c == '\r' || c == '\t';
}

std::string_view strip(std::string_view s)
{
    while (!s.empty() && isWhitespace(s.front()))
        s.remove_prefix(1);

    while (!s.empty() && isWhitespace(s.back()))
        s.remove_suffix(1);

    return s;
}

} // namespace Luau
