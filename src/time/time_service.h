#pragma once

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <functional>
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

// Called every poll iteration. Tracks both full-precision and seconds-precision
// time. The second callback fires once per second boundary.
class TimeService {
public:
  using Clock = std::chrono::system_clock;
  using TimePoint = Clock::time_point;
  using SecondPoint = std::chrono::time_point<Clock, std::chrono::seconds>;
  using TickCallback = std::function<void()>;

  TimeService();

  void setTickSecondCallback(TickCallback callback);
  [[nodiscard]] int pollTimeoutMs() const;
  void tick();

  [[nodiscard]] TimePoint now() const noexcept { return m_now; }

private:
  TickCallback m_secondCallback;
  TimePoint m_now{};
  SecondPoint m_nowSeconds{};
};
