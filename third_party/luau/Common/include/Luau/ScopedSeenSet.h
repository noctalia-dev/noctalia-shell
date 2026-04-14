// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

namespace Luau
{

template<typename SetType, typename Key>
struct ScopedSeenSet
{
    SetType& seen;
    Key key;

    ScopedSeenSet(SetType& seen, Key key)
        : seen(seen)
        , key(key)
    {
        seen.insert(key);
    }

    ~ScopedSeenSet()
    {
        seen.erase(key);
    }

    ScopedSeenSet(const ScopedSeenSet&) = delete;
    ScopedSeenSet& operator=(const ScopedSeenSet&) = delete;
};

} // namespace Luau
