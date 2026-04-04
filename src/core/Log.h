#pragma once

#include <format>
#include <string_view>
#include <utility>

enum class LogLevel { Debug, Info, Warn, Error };

namespace detail {
void logMessage(LogLevel level, std::string_view msg);
}

template<typename... Args>
void logDebug(std::format_string<Args...> fmt, Args&&... args) {
    detail::logMessage(LogLevel::Debug, std::format(fmt, std::forward<Args>(args)...));
}

template<typename... Args>
void logInfo(std::format_string<Args...> fmt, Args&&... args) {
    detail::logMessage(LogLevel::Info, std::format(fmt, std::forward<Args>(args)...));
}

template<typename... Args>
void logWarn(std::format_string<Args...> fmt, Args&&... args) {
    detail::logMessage(LogLevel::Warn, std::format(fmt, std::forward<Args>(args)...));
}

template<typename... Args>
void logError(std::format_string<Args...> fmt, Args&&... args) {
    detail::logMessage(LogLevel::Error, std::format(fmt, std::forward<Args>(args)...));
}

void setLogLevel(LogLevel level);
