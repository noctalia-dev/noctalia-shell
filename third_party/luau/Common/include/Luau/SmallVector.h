// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/Common.h"

#include <initializer_list>
#include <new>
#include <memory>
#include <type_traits>
#include <utility>

namespace Luau
{

template<typename T, unsigned N>
class SmallVector
{
    static_assert(std::is_nothrow_move_constructible<T>::value, "T must be nothrow move constructible");

public:
    using iterator = T*;
    using const_iterator = const T*;
    using value_type = T;
    using reference = T&;
    using const_reference = const T&;

    SmallVector()
    {
        ptr = reinterpret_cast<T*>(storage);
    }

    SmallVector(std::initializer_list<T> init)
        : SmallVector()
    {
        LUAU_ASSERT(unsigned(init.size()) == init.size());

        reserve(unsigned(init.size()));

        std::uninitialized_copy(init.begin(), init.end(), ptr);
        count = unsigned(init.size());
    }

    SmallVector(const SmallVector& other)
        : SmallVector()
    {
        reserve(other.count);

        std::uninitialized_copy(other.begin(), other.end(), ptr);
        count = other.count;
    }

    SmallVector(SmallVector&& other) noexcept
        : SmallVector()
    {
        if (!other.is_heap())
        {
            std::uninitialized_move(other.begin(), other.end(), ptr);
            count = other.count;

            other.clear();
        }
        else
        {
            ptr = other.ptr;
            max = other.max;
            count = other.count;

            other.ptr = reinterpret_cast<T*>(other.storage);
            other.max = N;
            other.count = 0;
        }
    }

    ~SmallVector()
    {
        clear();

        if (is_heap())
            ::operator delete(ptr);
    }

    SmallVector& operator=(const SmallVector& other)
    {
        if (this == &other)
            return *this;

        if (other.count <= count)
        {
            std::copy(other.begin(), other.end(), begin());

            while (count > other.count)
                ptr[--count].~T();
        }
        else
        {
            std::copy(other.begin(), other.begin() + count, begin());

            reserve(other.count);

            std::uninitialized_copy(other.begin() + count, other.end(), ptr + count);
            count = other.count;
        }

        return *this;
    }

    SmallVector& operator=(SmallVector&& other) noexcept
    {
        if (this != &other)
        {
            clear();

            if (!other.is_heap())
            {
                std::uninitialized_move(other.begin(), other.end(), begin());
                count = other.count;

                other.clear();
            }
            else
            {
                if (is_heap())
                    ::operator delete(ptr);

                ptr = other.ptr;
                max = other.max;
                count = other.count;

                other.ptr = reinterpret_cast<T*>(other.storage);
                other.max = N;
                other.count = 0;
            }
        }

        return *this;
    }

    template<typename... Args>
    reference emplace_back(Args&&... args)
    {
        if (count == max)
            grow(count + 1);

        new (&ptr[count]) T(std::forward<Args>(args)...);
        return ptr[count++];
    }

    void push_back(const T& val)
    {
        if (count == max)
            grow(count + 1);

        new (&ptr[count]) T(val);
        count++;
    }

    void push_back(T&& val)
    {
        if (count == max)
            grow(count + 1);

        new (&ptr[count]) T(std::move(val));
        count++;
    }

    T& front()
    {
        LUAU_ASSERT(count > 0);
        return ptr[0];
    }

    const T& front() const
    {
        LUAU_ASSERT(count > 0);
        return ptr[0];
    }

    T& back()
    {
        LUAU_ASSERT(count > 0);
        return ptr[count - 1];
    }

    const T& back() const
    {
        LUAU_ASSERT(count > 0);
        return ptr[count - 1];
    }

    bool empty() const noexcept
    {
        return count == 0;
    }

    unsigned size() const noexcept
    {
        return count;
    }

    unsigned capacity() const noexcept
    {
        return max;
    }

    void pop_back()
    {
        LUAU_ASSERT(count > 0);
        ptr[--count].~T();
    }

    void clear()
    {
        while (count > 0)
            ptr[--count].~T();
    }

    T* begin()
    {
        return ptr;
    }

    const T* begin() const
    {
        return ptr;
    }

    T* end()
    {
        return ptr + count;
    }

    const T* end() const
    {
        return ptr + count;
    }

    T* data()
    {
        return ptr;
    }
    const T* data() const
    {
        return ptr;
    }

    T& operator[](size_t index)
    {
        LUAU_ASSERT(index < count);

        return ptr[index];
    }

    const T& operator[](size_t index) const
    {
        LUAU_ASSERT(index < count);

        return ptr[index];
    }

    void resize(unsigned newSize)
    {
        if (newSize > count)
        {
            if (newSize > max)
                grow(newSize);

            for (unsigned i = count; i < newSize; ++i)
                new (&ptr[i]) T();
        }
        else
        {
            while (count > newSize)
                ptr[--count].~T();
        }

        count = newSize;
    }

    void reserve(unsigned reserveSize)
    {
        if (reserveSize > max)
            grow(reserveSize);
    }

private:
    bool is_heap() const
    {
        return ptr != reinterpret_cast<const T*>(storage);
    }

    void grow(unsigned newSize)
    {
        if (max + (max >> 1) > newSize)
            newSize = max + (max >> 1);
        else
            newSize += 4;

        LUAU_ASSERT(newSize < 0x40000000);

        void* raw = ::operator new(newSize * sizeof(T));
        T* newData = static_cast<T*>(raw);

        std::uninitialized_move(ptr, ptr + count, newData);

        for (unsigned i = 0; i < count; ++i)
            ptr[i].~T();

        if (is_heap())
            ::operator delete(ptr);

        ptr = newData;
        max = newSize;
    }

    T* ptr = nullptr;
    unsigned count = 0;
    unsigned max = N;

    alignas(T) unsigned char storage[N * sizeof(T)];
};

} // namespace Luau
