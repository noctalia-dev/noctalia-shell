#pragma once

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <string>

std::string formatTimeAgo(std::chrono::system_clock::time_point tp);

// Same wording as formatTimeAgo, but duration is computed from steady_clock (e.g. Notification::receivedTime).
[[nodiscard]] std::string formatElapsedSince(std::chrono::steady_clock::time_point since);

// Formats a duration as "{d}d {h}h {m}m" / "{h}h {m}m" / "{m}m" / "<1m".
[[nodiscard]] std::string formatDuration(std::chrono::seconds duration);

// Formats seconds as clock-style "M:SS" or "H:MM:SS". Returns "0:00" for <= 0.
[[nodiscard]] std::string formatClockTime(std::int64_t seconds);

// Formats the current local date using the locale's preferred format.
[[nodiscard]] std::string formatCurrentDate();

// First day of the week from the active LC_TIME locale (struct tm::tm_wday encoding: Sun=0 .. Sat=6).
[[nodiscard]] int localeFirstDayOfWeek();

// Formats current local time with a C++20 chrono format string (e.g. "{:%H:%M}").
// Bare chrono specs such as "%H:%M" are accepted, as are strftime-style no-pad
// numeric specifiers such as "%-I".
[[nodiscard]] std::string formatLocalTime(const char* fmt);

// Formats an ISO 8601 time string (e.g. "2026-05-09T06:23") using the given format.
[[nodiscard]] std::string formatIsoTime(std::string_view isoTime, const char* fmt);

// Formats a filesystem modification time as "YYYY-MM-DD HH:MM".
[[nodiscard]] std::string formatFileTime(const std::filesystem::file_time_type& time);
