// This file is part of the Luau programming language and is licensed under MIT License; see LICENSE.txt for details
#include "Luau/TimeTrace.h"

#include "Luau/StringUtils.h"

#include <algorithm>
#include <mutex>
#include <string>

#include <stdlib.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#ifdef __APPLE__
#include <mach/mach.h>
#include <mach/mach_time.h>
#endif

#include <time.h>

LUAU_FASTFLAGVARIABLE(DebugLuauTimeTracing)
namespace Luau
{
namespace TimeTrace
{
static double getClockPeriod()
{
#if defined(_WIN32)
    LARGE_INTEGER result = {};
    QueryPerformanceFrequency(&result);
    return 1.0 / double(result.QuadPart);
#elif defined(__APPLE__)
    mach_timebase_info_data_t result = {};
    mach_timebase_info(&result);
    return double(result.numer) / double(result.denom) * 1e-9;
#elif defined(__linux__) || defined(__FreeBSD__)
    return 1e-9;
#else
    return 1.0 / double(CLOCKS_PER_SEC);
#endif
}

static double getClockTimestamp()
{
#if defined(_WIN32)
    LARGE_INTEGER result = {};
    QueryPerformanceCounter(&result);
    return double(result.QuadPart);
#elif defined(__APPLE__)
    return double(mach_absolute_time());
#elif defined(__linux__) || defined(__FreeBSD__)
    timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * 1e9 + now.tv_nsec;
#else
    return double(clock());
#endif
}

double getClock()
{
    static double period = getClockPeriod();
    static double start = getClockTimestamp();

    return (getClockTimestamp() - start) * period;
}

uint32_t getClockMicroseconds()
{
    static double period = getClockPeriod() * 1e6;
    static double start = getClockTimestamp();

    return uint32_t((getClockTimestamp() - start) * period);
}
} // namespace TimeTrace
} // namespace Luau

#if defined(LUAU_ENABLE_TIME_TRACE)

namespace Luau
{
namespace TimeTrace
{
struct GlobalContext
{
    ~GlobalContext()
    {
        if (traceFile)
            fclose(traceFile);
    }

    std::mutex mutex;
    std::vector<ThreadContext*> threads;
    uint32_t nextThreadId = 0;
    std::vector<Token> tokens;
    FILE* traceFile = nullptr;

private:
    friend std::shared_ptr<GlobalContext> getGlobalContext();
    GlobalContext() = default;
};

std::shared_ptr<GlobalContext> getGlobalContext()
{
    static std::shared_ptr<GlobalContext> context = std::shared_ptr<GlobalContext>{new GlobalContext};
    return context;
}

uint16_t createToken(GlobalContext& context, const char* name, const char* category)
{
    std::scoped_lock lock(context.mutex);

    LUAU_ASSERT(context.tokens.size() < 64 * 1024);

    context.tokens.push_back({name, category});
    return uint16_t(context.tokens.size() - 1);
}

uint32_t createThread(GlobalContext& context, ThreadContext* threadContext)
{
    std::scoped_lock lock(context.mutex);

    context.threads.push_back(threadContext);

    return ++context.nextThreadId;
}

void releaseThread(GlobalContext& context, ThreadContext* threadContext)
{
    std::scoped_lock lock(context.mutex);

    if (auto it = std::find(context.threads.begin(), context.threads.end(), threadContext); it != context.threads.end())
        context.threads.erase(it);
}

void flushEvents(GlobalContext& context, uint32_t threadId, const std::vector<Event>& events, const std::vector<char>& data)
{
    std::scoped_lock lock(context.mutex);

    if (!context.traceFile)
    {
        context.traceFile = fopen("trace.json", "w");

        if (!context.traceFile)
            return;

        fprintf(context.traceFile, "[\n");
    }

    std::string temp;
    const unsigned tempReserve = 64 * 1024;
    temp.reserve(tempReserve);

    const char* rawData = data.data();

    // Formatting state
    bool unfinishedEnter = false;
    bool unfinishedArgs = false;

    for (const Event& ev : events)
    {
        switch (ev.type)
        {
        case EventType::Enter:
        {
            if (unfinishedArgs)
            {
                formatAppend(temp, "}");
                unfinishedArgs = false;
            }

            if (unfinishedEnter)
            {
                formatAppend(temp, "},\n");
                unfinishedEnter = false;
            }

            Token& token = context.tokens[ev.token];

            formatAppend(
                temp,
                R"({"name": "%s", "cat": "%s", "ph": "B", "ts": %u, "pid": 0, "tid": %u)",
                token.name,
                token.category,
                ev.data.microsec,
                threadId
            );
            unfinishedEnter = true;
        }
        break;
        case EventType::Leave:
            if (unfinishedArgs)
            {
                formatAppend(temp, "}");
                unfinishedArgs = false;
            }
            if (unfinishedEnter)
            {
                formatAppend(temp, "},\n");
                unfinishedEnter = false;
            }

            formatAppend(
                temp,
                R"({"ph": "E", "ts": %u, "pid": 0, "tid": %u},)"
                "\n",
                ev.data.microsec,
                threadId
            );
            break;
        case EventType::ArgName:
            LUAU_ASSERT(unfinishedEnter);

            if (!unfinishedArgs)
            {
                formatAppend(temp, R"(, "args": { "%s": )", rawData + ev.data.dataPos);
                unfinishedArgs = true;
            }
            else
            {
                formatAppend(temp, R"(, "%s": )", rawData + ev.data.dataPos);
            }
            break;
        case EventType::ArgValue:
            LUAU_ASSERT(unfinishedArgs);
            formatAppend(temp, R"("%s")", rawData + ev.data.dataPos);
            break;
        }

        // Don't want to hit the string capacity and reallocate
        if (temp.size() > tempReserve - 1024)
        {
            fwrite(temp.data(), 1, temp.size(), context.traceFile);
            temp.clear();
        }
    }

    if (unfinishedArgs)
    {
        formatAppend(temp, "}");
        unfinishedArgs = false;
    }
    if (unfinishedEnter)
    {
        formatAppend(temp, "},\n");
        unfinishedEnter = false;
    }

    fwrite(temp.data(), 1, temp.size(), context.traceFile);
    fflush(context.traceFile);
}

ThreadContext& getThreadContext()
{
    // Check custom provider that which might implement a custom TLS
    if (auto provider = threadContextProvider())
        return provider();

    thread_local ThreadContext context;
    return context;
}

uint16_t createScopeData(const char* name, const char* category)
{
    return createToken(*Luau::TimeTrace::getGlobalContext(), name, category);
}
} // namespace TimeTrace
} // namespace Luau

#endif
