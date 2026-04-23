#pragma once

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <string>

std::string formatTimeAgo(std::chrono::system_clock::time_point tp);

// Formats a duration as "{d}d {h}h {m}m" / "{h}h {m}m" / "{m}m" / "<1m".
[[nodiscard]] std::string formatDuration(std::chrono::seconds duration);

// Formats seconds as clock-style "M:SS" or "H:MM:SS". Returns "0:00" for <= 0.
[[nodiscard]] std::string formatClockTime(std::int64_t seconds);

// Formats the current local date using the locale's preferred format.
[[nodiscard]] std::string formatCurrentDate();

// Formats current local time with a C++20 chrono format string (e.g. "{:%H:%M}").
[[nodiscard]] std::string formatLocalTime(const char* fmt);

// Formats a filesystem modification time as "YYYY-MM-DD HH:MM".
[[nodiscard]] std::string formatFileTime(const std::filesystem::file_time_type& time);
