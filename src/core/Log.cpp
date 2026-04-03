#include "core/Log.hpp"

#include <cstdio>
#include <ctime>

namespace {

// Keep debug disabled by default; runtime debug service can enable it.
LogLevel gMinLevel = LogLevel::Info;

const char* levelTag(LogLevel level) {
    switch (level) {
        case LogLevel::Debug: return "\033[36mDBG\033[0m";
        case LogLevel::Info:  return "\033[32mINF\033[0m";
        case LogLevel::Warn:  return "\033[33mWRN\033[0m";
        case LogLevel::Error: return "\033[31mERR\033[0m";
    }
    return "???";
}

} // namespace

namespace detail {

void logMessage(LogLevel level, std::string_view msg) {
    if (level < gMinLevel) {
        return;
    }

    std::timespec ts{};
    std::timespec_get(&ts, TIME_UTC);
    std::tm tm{};
    localtime_r(&ts.tv_sec, &tm);

    std::fprintf(stderr, "%02d:%02d:%02d.%03ld [%s] %.*s\n",
        tm.tm_hour, tm.tm_min, tm.tm_sec,
        ts.tv_nsec / 1'000'000,
        levelTag(level),
        static_cast<int>(msg.size()), msg.data());
}

} // namespace detail

void setLogLevel(LogLevel level) {
    gMinLevel = level;
}
