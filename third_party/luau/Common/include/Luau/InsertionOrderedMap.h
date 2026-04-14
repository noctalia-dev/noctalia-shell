// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/Common.h"

#include <unordered_map>
#include <vector>
#include <type_traits>
#include <iterator>

namespace Luau
{

template<typename K, typename V>
struct InsertionOrderedMap
{
    static_assert(std::is_trivially_copyable_v<K>, "key must be trivially copyable");

private:
    using vec = std::vector<std::pair<K, V>>;

public:
    using iterator = typename vec::iterator;
    using const_iterator = typename vec::const_iterator;

    void insert(K k, V v)
    {
        if (indices.count(k) != 0)
            return;

        pairs.push_back(std::make_pair(k, std::move(v)));
        indices[k] = pairs.size() - 1;
    }

    void clear()
    {
        pairs.clear();
        indices.clear();
    }

    size_t size() const
    {
        LUAU_ASSERT(pairs.size() == indices.size());
        return pairs.size();
    }

    bool contains(const K& k) const
    {
        return indices.count(k) > 0;
    }

    const V* get(const K& k) const
    {
        auto it = indices.find(k);
        if (it == indices.end())
            return nullptr;
        else
            return &pairs.at(it->second).second;
    }

    V* get(const K& k)
    {
        auto it = indices.find(k);
        if (it == indices.end())
            return nullptr;
        else
            return &pairs.at(it->second).second;
    }

    V& operator[](const K& k)
    {
        auto it = indices.find(k);
        if (it == indices.end())
        {
            pairs.push_back(std::make_pair(k, V()));
            indices[k] = pairs.size() - 1;
            return pairs.back().second;
        }
        else
            return pairs.at(it->second).second;
    }

    const_iterator begin() const
    {
        return pairs.begin();
    }

    const_iterator end() const
    {
        return pairs.end();
    }

    iterator begin()
    {
        return pairs.begin();
    }

    iterator end()
    {
        return pairs.end();
    }

    const_iterator find(K k) const
    {
        auto indicesIt = indices.find(k);
        if (indicesIt == indices.end())
            return end();
        else
            return begin() + indicesIt->second;
    }

    iterator find(K k)
    {
        auto indicesIt = indices.find(k);
        if (indicesIt == indices.end())
            return end();
        else
            return begin() + indicesIt->second;
    }

    void erase(iterator it)
    {
        if (it == pairs.end())
            return;

        K k = it->first;
        auto indexIt = indices.find(k);
        if (indexIt == indices.end())
            return;

        size_t removed = indexIt->second;
        indices.erase(indexIt);
        pairs.erase(it);

        for (auto& [_, index] : indices)
        {
            if (index > removed)
                --index;
        }
    }

private:
    vec pairs;
    std::unordered_map<K, size_t> indices;
};

} // namespace Luau
