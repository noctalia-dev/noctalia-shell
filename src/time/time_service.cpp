#include "time/time_service.h"

#include <cstdint>
#include <ctime>
#include <format>
#include <fstream>

std::string formatTimeAgo(std::chrono::system_clock::time_point tp) {
  using namespace std::chrono;
  const auto secs = duration_cast<seconds>(system_clock::now() - tp).count();

  if (secs < 60) {
    return "just now";
  }
  if (secs < 3600) {
    const long mins = secs / 60;
    return std::to_string(mins) + " min ago";
  }
  if (secs < 86400) {
    const long hrs = secs / 3600;
    return std::to_string(hrs) + " hr ago";
  }
  if (secs < 7 * 86400) {
    const long days = secs / 86400;
    return std::to_string(days) + (days == 1 ? " day ago" : " days ago");
  }
  const std::time_t rawTime = system_clock::to_time_t(tp);
  std::tm localTime{};
  localtime_r(&rawTime, &localTime);
  char buffer[32];
  std::strftime(buffer, sizeof(buffer), "%b %e", &localTime);
  return buffer;
}

std::optional<std::chrono::seconds> systemUptime() {
  std::ifstream in{"/proc/uptime"};
  double up = 0.0;
  double idleDummy = 0.0;
  if (in >> up >> idleDummy) {
    return std::chrono::seconds{static_cast<std::int64_t>(up)};
  }
  return std::nullopt;
}

std::string formatDuration(std::chrono::seconds duration) {
  const std::uint64_t totalSeconds = static_cast<std::uint64_t>(duration.count());
  const std::uint64_t days = totalSeconds / 86400;
  std::uint64_t rem = totalSeconds % 86400;
  const std::uint64_t hours = rem / 3600;
  rem %= 3600;
  const std::uint64_t minutes = rem / 60;
  if (days > 0) {
    return std::format("{}d {}h {}m", days, hours, minutes);
  }
  if (hours > 0) {
    return std::format("{}h {}m", hours, minutes);
  }
  if (minutes > 0) {
    return std::format("{}m", minutes);
  }
  return "<1m";
}

void TimeService::setTickSecondCallback(TickCallback callback) { m_secondCallback = std::move(callback); }

int TimeService::pollTimeoutMs() const {
  using namespace std::chrono;
  const auto now = system_clock::now();
  const auto ms = duration_cast<milliseconds>(now.time_since_epoch()).count() % 1000;
  return static_cast<int>(1000 - ms);
}

void TimeService::tick() {
  using namespace std::chrono;
  m_now = system_clock::now();
  const auto floored = floor<seconds>(m_now);

  if (floored != m_nowSeconds) {
    m_nowSeconds = floored;
    if (m_secondCallback) {
      m_secondCallback();
    }
  }
}

std::string TimeService::format(const char* fmt) const {
  const auto local = std::chrono::current_zone()->to_local(m_nowSeconds);
  try {
    return std::vformat(fmt, std::make_format_args(local));
  } catch (const std::format_error&) {
    return fmt;
  }
}
