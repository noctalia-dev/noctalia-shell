// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#pragma once

#include "Luau/Common.h"

#include <vector>
#include <memory>

#include <stdint.h>
#include <string.h>

LUAU_FASTFLAG(DebugLuauTimeTracing)

namespace Luau
{
namespace TimeTrace
{
double getClock();
uint32_t getClockMicroseconds();
} // namespace TimeTrace
} // namespace Luau

#if defined(LUAU_ENABLE_TIME_TRACE)

namespace Luau
{
namespace TimeTrace
{
struct Token
{
    const char* name;
    const char* category;
};

enum class EventType : uint8_t
{
    Enter,
    Leave,

    ArgName,
    ArgValue,
};

struct Event
{
    EventType type;
    uint16_t token;

    union
    {
        uint32_t microsec; // 1 hour trace limit
        uint32_t dataPos;
    } data;
};

struct GlobalContext;
struct ThreadContext;

std::shared_ptr<GlobalContext> getGlobalContext();

uint16_t createToken(GlobalContext& context, const char* name, const char* category);
uint32_t createThread(GlobalContext& context, ThreadContext* threadContext);
void releaseThread(GlobalContext& context, ThreadContext* threadContext);
void flushEvents(GlobalContext& context, uint32_t threadId, const std::vector<Event>& events, const std::vector<char>& data);

struct ThreadContext
{
    ThreadContext()
        : globalContext(getGlobalContext())
    {
        threadId = createThread(*globalContext, this);
    }

    ~ThreadContext()
    {
        if (!events.empty())
            flushEvents();

        releaseThread(*globalContext, this);
    }

    void flushEvents()
    {
        static uint16_t flushToken = createToken(*globalContext, "flushEvents", "TimeTrace");

        events.push_back({EventType::Enter, flushToken, {getClockMicroseconds()}});

        TimeTrace::flushEvents(*globalContext, threadId, events, data);

        events.clear();
        data.clear();

        events.push_back({EventType::Leave, 0, {getClockMicroseconds()}});
    }

    void eventEnter(uint16_t token)
    {
        eventEnter(token, getClockMicroseconds());
    }

    void eventEnter(uint16_t token, uint32_t microsec)
    {
        events.push_back({EventType::Enter, token, {microsec}});
    }

    void eventLeave()
    {
        eventLeave(getClockMicroseconds());
    }

    void eventLeave(uint32_t microsec)
    {
        events.push_back({EventType::Leave, 0, {microsec}});

        if (events.size() > kEventFlushLimit)
            flushEvents();
    }

    void eventArgument(const char* name, const char* value)
    {
        uint32_t pos = uint32_t(data.size());
        data.insert(data.end(), name, name + strlen(name) + 1);
        events.push_back({EventType::ArgName, 0, {pos}});

        pos = uint32_t(data.size());
        data.insert(data.end(), value, value + strlen(value) + 1);
        events.push_back({EventType::ArgValue, 0, {pos}});
    }

    std::shared_ptr<GlobalContext> globalContext;
    uint32_t threadId;
    std::vector<Event> events;
    std::vector<char> data;

    static constexpr size_t kEventFlushLimit = 8192;
};

using ThreadContextProvider = ThreadContext& (*)();

inline ThreadContextProvider& threadContextProvider()
{
    static ThreadContextProvider handler = nullptr;
    return handler;
}

ThreadContext& getThreadContext();

struct Scope
{
    explicit Scope(uint16_t token)
        : context(getThreadContext())
    {
        if (!FFlag::DebugLuauTimeTracing)
            return;

        context.eventEnter(token);
    }

    ~Scope()
    {
        if (!FFlag::DebugLuauTimeTracing)
            return;

        context.eventLeave();
    }

    ThreadContext& context;
};

struct OptionalTailScope
{
    explicit OptionalTailScope(uint16_t token, uint32_t threshold)
        : context(getThreadContext())
        , token(token)
        , threshold(threshold)
    {
        if (!FFlag::DebugLuauTimeTracing)
            return;

        pos = uint32_t(context.events.size());
        microsec = getClockMicroseconds();
    }

    ~OptionalTailScope()
    {
        if (!FFlag::DebugLuauTimeTracing)
            return;

        if (pos == context.events.size())
        {
            uint32_t curr = getClockMicroseconds();

            if (curr - microsec > threshold)
            {
                context.eventEnter(token, microsec);
                context.eventLeave(curr);
            }
        }
    }

    ThreadContext& context;
    uint16_t token;
    uint32_t threshold;
    uint32_t microsec;
    uint32_t pos;
};

LUAU_NOINLINE uint16_t createScopeData(const char* name, const char* category);

} // namespace TimeTrace
} // namespace Luau

// Regular scope
#define LUAU_TIMETRACE_SCOPE(name, category) \
    static uint16_t lttScopeStatic = Luau::TimeTrace::createScopeData(name, category); \
    Luau::TimeTrace::Scope lttScope(lttScopeStatic)

// A scope without nested scopes that may be skipped if the time it took is less than the threshold
#define LUAU_TIMETRACE_OPTIONAL_TAIL_SCOPE(name, category, microsec) \
    static uint16_t lttScopeStaticOptTail = Luau::TimeTrace::createScopeData(name, category); \
    Luau::TimeTrace::OptionalTailScope lttScope(lttScopeStaticOptTail, microsec)

// Extra key/value data can be added to regular scopes
#define LUAU_TIMETRACE_ARGUMENT(name, value) \
    do \
    { \
        if (FFlag::DebugLuauTimeTracing) \
            lttScope.context.eventArgument(name, value); \
    } while (false)

#else

#define LUAU_TIMETRACE_SCOPE(name, category)
#define LUAU_TIMETRACE_OPTIONAL_TAIL_SCOPE(name, category, microsec)
#define LUAU_TIMETRACE_ARGUMENT(name, value) \
    do \
    { \
    } while (false)

#endif
