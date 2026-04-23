#include "time/time_format.h"

#include <chrono>
#include <cstdint>
#include <ctime>
#include <format>
#include <langinfo.h>
#include <locale>

std::string formatLocalTime(const char* fmt) {
  using namespace std::chrono;
  const auto now = floor<seconds>(system_clock::now());
  const auto local = current_zone()->to_local(now);
  try {
    return std::vformat(std::locale(""), fmt, std::make_format_args(local));
  } catch (...) {
    return fmt;
  }
}

std::string formatCurrentDate() {
  std::string fmt = "%A, ";
  fmt += nl_langinfo(D_FMT);
  for (std::size_t pos = 0; (pos = fmt.find("%y", pos)) != std::string::npos;) {
    fmt.replace(pos, 2, "%Y");
    pos += 2;
  }
  const std::time_t now = std::time(nullptr);
  const std::tm local = *std::localtime(&now);
  char buf[64]{};
  std::strftime(buf, sizeof(buf), fmt.c_str(), &local);
  return std::string(buf);
}

std::string formatClockTime(std::int64_t seconds) {
  if (seconds <= 0) {
    return "0:00";
  }
  const std::int64_t totalMinutes = seconds / 60;
  const std::int64_t hours = totalMinutes / 60;
  const std::int64_t minutes = totalMinutes % 60;
  const std::int64_t secs = seconds % 60;
  if (hours > 0) {
    return std::format("{}:{:02}:{:02}", hours, minutes, secs);
  }
  return std::format("{}:{:02}", minutes, secs);
}

std::string formatFileTime(const std::filesystem::file_time_type& time) {
  if (time == std::filesystem::file_time_type{}) {
    return "Unknown";
  }
  const auto systemNow = std::chrono::system_clock::now();
  const auto fileNow = std::filesystem::file_time_type::clock::now();
  const auto systemTime = std::chrono::time_point_cast<std::chrono::system_clock::duration>(time - fileNow + systemNow);
  const std::time_t value = std::chrono::system_clock::to_time_t(systemTime);
  std::tm tm{};
  localtime_r(&value, &tm);
  char buf[32];
  if (std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M", &tm) == 0) {
    return "Unknown";
  }
  return buf;
}

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
