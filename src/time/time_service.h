#pragma once

#include <chrono>
#include <functional>
#include <optional>
#include <string>

std::string formatTimeAgo(std::chrono::system_clock::time_point tp);

// Returns system uptime (from /proc/uptime), or nullopt if unavailable.
[[nodiscard]] std::optional<std::chrono::seconds> systemUptime();

// Formats a duration as "{d}d {h}h {m}m" / "{h}h {m}m" / "{m}m" / "<1m".
[[nodiscard]] std::string formatDuration(std::chrono::seconds duration);

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
  [[nodiscard]] std::string format(const char* fmt) const;

private:
  TickCallback m_secondCallback;
  TimePoint m_now{};
  SecondPoint m_nowSeconds{};
};
