// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include <initializer_list>
#include <new>
#include <type_traits>
#include <utility>

#include <stddef.h>

namespace Luau
{

template<typename... Ts>
class Variant
{
    static_assert(sizeof...(Ts) > 0, "variant must have at least 1 type (empty variants are ill-formed)");
    static_assert(std::disjunction_v<std::is_void<Ts>...> == false, "variant does not allow void as an alternative type");
    static_assert(std::disjunction_v<std::is_reference<Ts>...> == false, "variant does not allow references as an alternative type");
    static_assert(std::disjunction_v<std::is_array<Ts>...> == false, "variant does not allow arrays as an alternative type");

public:
    template<typename T>
    static constexpr int getTypeId()
    {
        using TT = std::decay_t<T>;

        constexpr int N = sizeof...(Ts);
        constexpr bool is[N] = {std::is_same_v<TT, Ts>...};

        for (int i = 0; i < N; ++i)
            if (is[i])
                return i;

        return -1;
    }

private:
    template<typename T, typename... Tail>
    struct First
    {
        using type = T;
    };

public:
    using first_alternative = typename First<Ts...>::type;

    template<typename T>
    static constexpr bool is_part_of_v = std::disjunction_v<typename std::is_same<std::decay_t<Ts>, T>...>;

    Variant()
    {
        static_assert(std::is_default_constructible_v<first_alternative>, "first alternative type must be default constructible");
        typeId = 0;
        new (&storage) first_alternative();
    }

    template<typename T>
    Variant(T&& value, std::enable_if_t<getTypeId<T>() >= 0>* = 0)
    {
        using TT = std::decay_t<T>;

        constexpr int tid = getTypeId<T>();
        typeId = tid;
        new (&storage) TT(std::forward<T>(value));
    }

    Variant(const Variant& other)
    {
        static constexpr FnCopy table[sizeof...(Ts)] = {&fnCopy<Ts>...};

        typeId = other.typeId;
        table[typeId](&storage, &other.storage);
    }

    Variant(Variant&& other) noexcept
    {
        typeId = other.typeId;
        tableMove[typeId](&storage, &other.storage);
    }

    ~Variant()
    {
        tableDtor[typeId](&storage);
    }

    Variant& operator=(const Variant& other)
    {
        Variant copy(other);
        // static_cast<T&&> is equivalent to std::move() but faster in Debug
        return *this = static_cast<Variant&&>(copy);
    }

    Variant& operator=(Variant&& other) noexcept
    {
        if (this != &other)
        {
            tableDtor[typeId](&storage);
            typeId = other.typeId;
            tableMove[typeId](&storage, &other.storage); // nothrow
        }
        return *this;
    }

    template<typename T, typename... Args>
    T& emplace(Args&&... args)
    {
        using TT = std::decay_t<T>;
        constexpr int tid = getTypeId<T>();
        static_assert(tid >= 0, "unsupported T");

        tableDtor[typeId](&storage);
        typeId = tid;
        new (&storage) TT{std::forward<Args>(args)...};

        return *reinterpret_cast<T*>(&storage);
    }

    template<typename T>
    const T* get_if() const
    {
        constexpr int tid = getTypeId<T>();
        static_assert(tid >= 0, "unsupported T");

        return tid == typeId ? reinterpret_cast<const T*>(&storage) : nullptr;
    }

    template<typename T>
    T* get_if()
    {
        constexpr int tid = getTypeId<T>();
        static_assert(tid >= 0, "unsupported T");

        return tid == typeId ? reinterpret_cast<T*>(&storage) : nullptr;
    }

    bool valueless_by_exception() const
    {
        return false;
    }

    int index() const
    {
        return typeId;
    }

    bool operator==(const Variant& other) const
    {
        static constexpr FnPred table[sizeof...(Ts)] = {&fnPredEq<Ts>...};

        return typeId == other.typeId && table[typeId](&storage, &other.storage);
    }

    bool operator!=(const Variant& other) const
    {
        return !(*this == other);
    }

private:
    static constexpr size_t cmax(std::initializer_list<size_t> l)
    {
        size_t res = 0;
        for (size_t i : l)
            res = (res < i) ? i : res;
        return res;
    }

    static constexpr size_t storageSize = cmax({sizeof(Ts)...});
    static constexpr size_t storageAlign = cmax({alignof(Ts)...});

    using FnCopy = void (*)(void*, const void*);
    using FnMove = void (*)(void*, void*) noexcept;
    using FnDtor = void (*)(void*);
    using FnPred = bool (*)(const void*, const void*);

    template<typename T>
    static void fnCopy(void* dst, const void* src)
    {
        new (dst) T(*static_cast<const T*>(src));
    }

    template<typename T>
    static void fnMove(void* dst, void* src) noexcept
    {
        // static_cast<T&&> is equivalent to std::move() but faster in Debug
        new (dst) T(static_cast<T&&>(*static_cast<T*>(src)));
    }

    template<typename T>
    static void fnDtor(void* dst)
    {
        static_cast<T*>(dst)->~T();
    }

    template<typename T>
    static bool fnPredEq(const void* lhs, const void* rhs)
    {
        return *static_cast<const T*>(lhs) == *static_cast<const T*>(rhs);
    }

    static constexpr FnMove tableMove[sizeof...(Ts)] = {&fnMove<Ts>...};
    static constexpr FnDtor tableDtor[sizeof...(Ts)] = {&fnDtor<Ts>...};

    int typeId;
    alignas(storageAlign) char storage[storageSize];

    template<class Visitor, typename... _Ts>
    friend auto visit(Visitor&& vis, const Variant<_Ts...>& var);
    template<class Visitor, typename... _Ts>
    friend auto visit(Visitor&& vis, Variant<_Ts...>& var);
};

template<typename T, typename... Ts>
const T* get_if(const Variant<Ts...>* var)
{
    return var ? var->template get_if<T>() : nullptr;
}

template<typename T, typename... Ts>
T* get_if(Variant<Ts...>* var)
{
    return var ? var->template get_if<T>() : nullptr;
}

template<typename Visitor, typename Result, typename T>
static void fnVisitR(Visitor& vis, Result& dst, std::conditional_t<std::is_const_v<T>, const void, void>* src)
{
    dst = vis(*static_cast<T*>(src));
}

template<typename Visitor, typename T>
static void fnVisitV(Visitor& vis, std::conditional_t<std::is_const_v<T>, const void, void>* src)
{
    vis(*static_cast<T*>(src));
}

template<class Visitor, typename... Ts>
auto visit(Visitor&& vis, const Variant<Ts...>& var)
{
    static_assert(std::conjunction_v<std::is_invocable<Visitor, Ts>...>, "visitor must accept every alternative as an argument");

    using Result = std::invoke_result_t<Visitor, typename Variant<Ts...>::first_alternative>;
    static_assert(
        std::conjunction_v<std::is_same<Result, std::invoke_result_t<Visitor, Ts>>...>, "visitor result type must be consistent between alternatives"
    );

    if constexpr (std::is_same_v<Result, void>)
    {
        using FnVisitV = void (*)(Visitor&, const void*);
        static const FnVisitV tableVisit[sizeof...(Ts)] = {&fnVisitV<Visitor, const Ts>...};

        tableVisit[var.typeId](vis, &var.storage);
    }
    else
    {
        using FnVisitR = void (*)(Visitor&, Result&, const void*);
        static const FnVisitR tableVisit[sizeof...(Ts)] = {&fnVisitR<Visitor, Result, const Ts>...};

        Result res;
        tableVisit[var.typeId](vis, res, &var.storage);
        return res;
    }
}

template<class Visitor, typename... Ts>
auto visit(Visitor&& vis, Variant<Ts...>& var)
{
    static_assert(std::conjunction_v<std::is_invocable<Visitor, Ts&>...>, "visitor must accept every alternative as an argument");

    using Result = std::invoke_result_t<Visitor, typename Variant<Ts...>::first_alternative&>;
    static_assert(
        std::conjunction_v<std::is_same<Result, std::invoke_result_t<Visitor, Ts&>>...>, "visitor result type must be consistent between alternatives"
    );

    if constexpr (std::is_same_v<Result, void>)
    {
        using FnVisitV = void (*)(Visitor&, void*);
        static const FnVisitV tableVisit[sizeof...(Ts)] = {&fnVisitV<Visitor, Ts>...};

        tableVisit[var.typeId](vis, &var.storage);
    }
    else
    {
        using FnVisitR = void (*)(Visitor&, Result&, void*);
        static const FnVisitR tableVisit[sizeof...(Ts)] = {&fnVisitR<Visitor, Result, Ts>...};

        Result res;
        tableVisit[var.typeId](vis, res, &var.storage);
        return res;
    }
}

template<typename... Ts>
struct overloaded : Ts...
{
    using Ts::operator()...;
};
template<typename... Ts>
overloaded(Ts...) -> overloaded<Ts...>;

template<class>
inline constexpr bool always_false_v = false;

} // namespace Luau
