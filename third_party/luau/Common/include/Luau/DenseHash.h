// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/HashUtil.h"
#include "Luau/Common.h"

#include <stddef.h>
#include <functional>
#include <utility>
#include <stdint.h>

namespace Luau
{

// Internal implementation of DenseHashSet and DenseHashMap
namespace detail
{

template<typename Key, typename Item, typename MutableItem, typename ItemInterface, typename Hash, typename Eq>
class DenseHashTable
{
public:
    class const_iterator;
    class iterator;

    explicit DenseHashTable(const Key& empty_key, size_t buckets = 0)
        : data(nullptr)
        , capacity(0)
        , count(0)
        , empty_key(empty_key)
    {
        // validate that equality operator is at least somewhat functional
        LUAU_ASSERT(eq(empty_key, empty_key));
        // buckets has to be power-of-two or zero
        LUAU_ASSERT((buckets & (buckets - 1)) == 0);

        if (buckets)
        {
            data = static_cast<Item*>(::operator new(sizeof(Item) * buckets));
            capacity = buckets;

            ItemInterface::fill(data, buckets, empty_key);
        }
    }

    ~DenseHashTable()
    {
        if (data)
            destroy();
    }

    DenseHashTable(const DenseHashTable& other)
        : data(nullptr)
        , capacity(0)
        , count(other.count)
        , empty_key(other.empty_key)
    {
        if (other.capacity)
        {
            data = static_cast<Item*>(::operator new(sizeof(Item) * other.capacity));

            for (size_t i = 0; i < other.capacity; ++i)
            {
                new (&data[i]) Item(other.data[i]);
                capacity = i + 1; // if Item copy throws, capacity will note the number of initialized objects for destroy() to clean up
            }
        }
    }

    DenseHashTable(DenseHashTable&& other)
        : data(other.data)
        , capacity(other.capacity)
        , count(other.count)
        , empty_key(other.empty_key)
    {
        other.data = nullptr;
        other.capacity = 0;
        other.count = 0;
    }

    DenseHashTable& operator=(DenseHashTable&& other)
    {
        if (this != &other)
        {
            if (data)
                destroy();

            data = other.data;
            capacity = other.capacity;
            count = other.count;
            empty_key = other.empty_key;

            other.data = nullptr;
            other.capacity = 0;
            other.count = 0;
        }

        return *this;
    }

    DenseHashTable& operator=(const DenseHashTable& other)
    {
        if (this != &other)
        {
            DenseHashTable copy(other);
            *this = std::move(copy);
        }

        return *this;
    }

    void clear(size_t thresholdToDestroy = 32)
    {
        if (count == 0)
            return;

        if (capacity > thresholdToDestroy)
        {
            destroy();
        }
        else
        {
            ItemInterface::destroy(data, capacity);
            ItemInterface::fill(data, capacity, empty_key);
        }

        count = 0;
    }

    void destroy()
    {
        ItemInterface::destroy(data, capacity);

        ::operator delete(data);
        data = nullptr;

        capacity = 0;
    }

    Item* insert_unsafe(const Key& key)
    {
        // It is invalid to insert empty_key into the table since it acts as a "entry does not exist" marker
        LUAU_ASSERT(!eq(key, empty_key));

        size_t hashmod = capacity - 1;
        size_t bucket = hasher(key) & hashmod;

        for (size_t probe = 0; probe <= hashmod; ++probe)
        {
            Item& probe_item = data[bucket];

            // Element does not exist, insert here
            if (eq(ItemInterface::getKey(probe_item), empty_key))
            {
                ItemInterface::setKey(probe_item, key);
                count++;
                return &probe_item;
            }

            // Element already exists
            if (eq(ItemInterface::getKey(probe_item), key))
            {
                return &probe_item;
            }

            // Hash collision, quadratic probing
            bucket = (bucket + probe + 1) & hashmod;
        }

        // Hash table is full - this should not happen
        LUAU_ASSERT(false);
        return NULL;
    }

    const Item* find(const Key& key) const
    {
        if (count == 0)
            return 0;
        if (eq(key, empty_key))
            return 0;

        size_t hashmod = capacity - 1;
        size_t bucket = hasher(key) & hashmod;

        for (size_t probe = 0; probe <= hashmod; ++probe)
        {
            const Item& probe_item = data[bucket];

            // Element exists
            if (eq(ItemInterface::getKey(probe_item), key))
                return &probe_item;

            // Element does not exist
            if (eq(ItemInterface::getKey(probe_item), empty_key))
                return NULL;

            // Hash collision, quadratic probing
            bucket = (bucket + probe + 1) & hashmod;
        }

        // Hash table is full - this should not happen
        LUAU_ASSERT(false);
        return NULL;
    }

    void rehash()
    {
        size_t newsize = capacity == 0 ? 16 : capacity * 2;

        DenseHashTable newtable(empty_key, newsize);

        for (size_t i = 0; i < capacity; ++i)
        {
            const Key& key = ItemInterface::getKey(data[i]);

            if (!eq(key, empty_key))
            {
                Item* item = newtable.insert_unsafe(key);
                *item = std::move(data[i]);
            }
        }

        LUAU_ASSERT(count == newtable.count);

        std::swap(data, newtable.data);
        std::swap(capacity, newtable.capacity);
    }

    void rehash_if_full(const Key& key)
    {
        if (count >= capacity * 3 / 4 && !find(key))
        {
            rehash();
        }
    }

    const_iterator begin() const
    {
        size_t start = 0;

        while (start < capacity && eq(ItemInterface::getKey(data[start]), empty_key))
            start++;

        return const_iterator(this, start);
    }

    const_iterator end() const
    {
        return const_iterator(this, capacity);
    }

    iterator begin()
    {
        size_t start = 0;

        while (start < capacity && eq(ItemInterface::getKey(data[start]), empty_key))
            start++;

        return iterator(this, start);
    }

    iterator end()
    {
        return iterator(this, capacity);
    }

    size_t size() const
    {
        return count;
    }

    class const_iterator
    {
    public:
        using value_type = Item;
        using reference = Item&;
        using pointer = Item*;
        using difference_type = ptrdiff_t;
        using iterator_category = std::forward_iterator_tag;

        const_iterator()
            : set(0)
            , index(0)
        {
        }

        const_iterator(const DenseHashTable<Key, Item, MutableItem, ItemInterface, Hash, Eq>* set, size_t index)
            : set(set)
            , index(index)
        {
        }

        const Item& operator*() const
        {
            return set->data[index];
        }

        const Item* operator->() const
        {
            return &set->data[index];
        }

        bool operator==(const const_iterator& other) const
        {
            return set == other.set && index == other.index;
        }

        bool operator!=(const const_iterator& other) const
        {
            return set != other.set || index != other.index;
        }

        const_iterator& operator++()
        {
            size_t size = set->capacity;

            do
            {
                index++;
            } while (index < size && set->eq(ItemInterface::getKey(set->data[index]), set->empty_key));

            return *this;
        }

        const_iterator operator++(int)
        {
            const_iterator res = *this;
            ++*this;
            return res;
        }

    private:
        const DenseHashTable<Key, Item, MutableItem, ItemInterface, Hash, Eq>* set;
        size_t index;
    };

    class iterator
    {
    public:
        using value_type = MutableItem;
        using reference = MutableItem&;
        using pointer = MutableItem*;
        using difference_type = ptrdiff_t;
        using iterator_category = std::forward_iterator_tag;

        iterator()
            : set(0)
            , index(0)
        {
        }

        iterator(DenseHashTable<Key, Item, MutableItem, ItemInterface, Hash, Eq>* set, size_t index)
            : set(set)
            , index(index)
        {
        }

        MutableItem& operator*() const
        {
            return *reinterpret_cast<MutableItem*>(&set->data[index]);
        }

        MutableItem* operator->() const
        {
            return reinterpret_cast<MutableItem*>(&set->data[index]);
        }

        bool operator==(const iterator& other) const
        {
            return set == other.set && index == other.index;
        }

        bool operator!=(const iterator& other) const
        {
            return set != other.set || index != other.index;
        }

        iterator& operator++()
        {
            size_t size = set->capacity;

            do
            {
                index++;
            } while (index < size && set->eq(ItemInterface::getKey(set->data[index]), set->empty_key));

            return *this;
        }

        iterator operator++(int)
        {
            iterator res = *this;
            ++*this;
            return res;
        }

    private:
        DenseHashTable<Key, Item, MutableItem, ItemInterface, Hash, Eq>* set;
        size_t index;
    };

private:
    Item* data;
    size_t capacity;
    size_t count;
    Key empty_key;
    Hash hasher;
    Eq eq;
};

template<typename Key>
struct ItemInterfaceSet
{
    static const Key& getKey(const Key& item)
    {
        return item;
    }

    static void setKey(Key& item, const Key& key)
    {
        item = key;
    }

    static void fill(Key* data, size_t count, const Key& key)
    {
        for (size_t i = 0; i < count; ++i)
            new (&data[i]) Key(key);
    }

    static void destroy(Key* data, size_t count)
    {
        for (size_t i = 0; i < count; ++i)
            data[i].~Key();
    }
};

template<typename Key, typename Value>
struct ItemInterfaceMap
{
    static const Key& getKey(const std::pair<Key, Value>& item)
    {
        return item.first;
    }

    static void setKey(std::pair<Key, Value>& item, const Key& key)
    {
        item.first = key;
    }

    static void fill(std::pair<Key, Value>* data, size_t count, const Key& key)
    {
        for (size_t i = 0; i < count; ++i)
        {
            new (&data[i].first) Key(key);
            new (&data[i].second) Value();
        }
    }

    static void destroy(std::pair<Key, Value>* data, size_t count)
    {
        for (size_t i = 0; i < count; ++i)
        {
            data[i].first.~Key();
            data[i].second.~Value();
        }
    }
};

} // namespace detail

// This is a faster alternative of unordered_set, but it does not implement the same interface (i.e. it does not support erasing)
template<typename Key, typename Hash = detail::DenseHashDefault<Key>, typename Eq = std::equal_to<Key>>
class DenseHashSet
{
    typedef detail::DenseHashTable<Key, Key, Key, detail::ItemInterfaceSet<Key>, Hash, Eq> Impl;
    Impl impl;

public:
    typedef typename Impl::const_iterator const_iterator;
    typedef typename Impl::iterator iterator;

    explicit DenseHashSet(const Key& empty_key, size_t buckets = 0)
        : impl(empty_key, buckets)
    {
    }

    void clear()
    {
        impl.clear();
    }

    const Key& insert(const Key& key)
    {
        impl.rehash_if_full(key);
        return *impl.insert_unsafe(key);
    }

    const Key* find(const Key& key) const
    {
        return impl.find(key);
    }

    bool contains(const Key& key) const
    {
        return impl.find(key) != 0;
    }

    size_t size() const
    {
        return impl.size();
    }

    bool empty() const
    {
        return impl.size() == 0;
    }

    const_iterator begin() const
    {
        return impl.begin();
    }

    const_iterator end() const
    {
        return impl.end();
    }

    iterator begin()
    {
        return impl.begin();
    }

    iterator end()
    {
        return impl.end();
    }

    bool operator==(const DenseHashSet<Key, Hash, Eq>& other) const
    {
        if (size() != other.size())
            return false;

        for (const Key& k : *this)
        {
            if (!other.contains(k))
                return false;
        }

        return true;
    }

    bool operator!=(const DenseHashSet<Key, Hash, Eq>& other) const
    {
        return !(*this == other);
    }
};

// This is a faster alternative of unordered_map, but it does not implement the same interface (i.e. it does not support erasing and has
// contains() instead of find())
template<typename Key, typename Value, typename Hash = detail::DenseHashDefault<Key>, typename Eq = std::equal_to<Key>>
class DenseHashMap
{
    typedef detail::DenseHashTable<Key, std::pair<Key, Value>, std::pair<const Key, Value>, detail::ItemInterfaceMap<Key, Value>, Hash, Eq> Impl;
    Impl impl;

public:
    typedef typename Impl::const_iterator const_iterator;
    typedef typename Impl::iterator iterator;

    explicit DenseHashMap(const Key& empty_key, size_t buckets = 0)
        : impl(empty_key, buckets)
    {
    }

    void clear(size_t thresholdToDestroy = 32)
    {
        impl.clear(thresholdToDestroy);
    }

    // Note: this reference is invalidated by any insert operation (i.e. operator[])
    Value& operator[](const Key& key)
    {
        impl.rehash_if_full(key);
        return impl.insert_unsafe(key)->second;
    }

    // Note: this pointer is invalidated by any insert operation (i.e. operator[])
    const Value* find(const Key& key) const
    {
        const std::pair<Key, Value>* result = impl.find(key);

        return result ? &result->second : NULL;
    }

    // Note: this pointer is invalidated by any insert operation (i.e. operator[])
    Value* find(const Key& key)
    {
        const std::pair<Key, Value>* result = impl.find(key);

        return result ? const_cast<Value*>(&result->second) : NULL;
    }

    bool contains(const Key& key) const
    {
        return impl.find(key) != 0;
    }

    std::pair<Value&, bool> try_insert(const Key& key, const Value& value)
    {
        impl.rehash_if_full(key);

        size_t before = impl.size();
        std::pair<Key, Value>* slot = impl.insert_unsafe(key);

        // Value is fresh if container count has increased
        bool fresh = impl.size() > before;

        if (fresh)
            slot->second = value;

        return std::make_pair(std::ref(slot->second), fresh);
    }

    std::pair<Value&, bool> try_insert(const Key& key, Value&& value)
    {
        impl.rehash_if_full(key);

        size_t before = impl.size();
        std::pair<Key, Value>* slot = impl.insert_unsafe(key);

        // Value is fresh if container count has increased
        bool fresh = impl.size() > before;

        if (fresh)
            slot->second = std::move(value);

        return std::make_pair(std::ref(slot->second), fresh);
    }

    size_t size() const
    {
        return impl.size();
    }

    bool empty() const
    {
        return impl.size() == 0;
    }

    const_iterator begin() const
    {
        return impl.begin();
    }

    const_iterator end() const
    {
        return impl.end();
    }

    iterator begin()
    {
        return impl.begin();
    }

    iterator end()
    {
        return impl.end();
    }
};

} // namespace Luau
