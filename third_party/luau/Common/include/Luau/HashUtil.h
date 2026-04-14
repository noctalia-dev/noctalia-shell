#pragma once

#include "Luau/Common.h"

#include <stddef.h>
#include <stdint.h>

#include <functional>
#include <type_traits>
#include <utility>

namespace Luau
{

struct DenseHashPointer
{
    size_t operator()(const void* key) const
    {
        return (uintptr_t(key) >> 4) ^ (uintptr_t(key) >> 9);
    }
};

namespace detail
{

template<typename T>
using DenseHashDefault = std::conditional_t<std::is_pointer_v<T>, DenseHashPointer, std::hash<T>>;

} // namespace detail

inline void hashCombine(size_t& seed, size_t hash)
{
    // Golden Ratio constant used for better hash scattering
    // See https://softwareengineering.stackexchange.com/a/402543
    seed ^= hash + 0x9e3779b9 + (seed << 6) + (seed >> 2);
}

template<typename T1, typename T2, typename H1 = detail::DenseHashDefault<T1>, typename H2 = detail::DenseHashDefault<T2>>
struct PairHash
{
    std::size_t operator()(const std::pair<T1, T2>& p) const noexcept
    {
        std::size_t seed = 0;
        hashCombine(seed, h1(p.first));
        hashCombine(seed, h2(p.second));
        return seed;
    }

private:
    H1 h1;
    H2 h2;
};

} // namespace Luau
