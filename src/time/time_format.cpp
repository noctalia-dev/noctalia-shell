#include "time/time_format.h"

#include "i18n/i18n.h"

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <ctime>
#include <format>
#include <langinfo.h>
#include <locale>
#include <optional>
#include <string_view>

namespace {

  bool shouldUseStrftimeCompat(std::string_view fmt) {
    return fmt.find("%-") != std::string_view::npos ||
           (fmt.find('{') == std::string_view::npos && fmt.find('%') != std::string_view::npos);
  }

  std::string strftimeSpec(std::string_view spec, const std::tm& local) {
    std::string fmt(spec);
    std::size_t size = std::max<std::size_t>(64, fmt.size() * 4 + 16);
    for (int attempt = 0; attempt < 4; ++attempt) {
      std::string buffer(size, '\0');
      std::tm copy = local;
      const std::size_t written = std::strftime(buffer.data(), buffer.size(), fmt.c_str(), &copy);
      if (written > 0 || fmt.empty()) {
        buffer.resize(written);
        return buffer;
      }
      size *= 2;
    }
    return {};
  }

  std::optional<std::string> formatStrftimeCompat(std::string_view fmt, const std::tm& local) {
    if (!shouldUseStrftimeCompat(fmt)) {
      return std::nullopt;
    }
    if (fmt.find('{') == std::string_view::npos) {
      return strftimeSpec(fmt, local);
    }

    std::string out;
    out.reserve(fmt.size());
    bool formattedField = false;
    for (std::size_t i = 0; i < fmt.size();) {
      if (fmt[i] == '{' && i + 1 < fmt.size() && fmt[i + 1] == '{') {
        out.push_back('{');
        i += 2;
        continue;
      }
      if (fmt[i] == '}' && i + 1 < fmt.size() && fmt[i + 1] == '}') {
        out.push_back('}');
        i += 2;
        continue;
      }
      if (fmt[i] != '{') {
        out.push_back(fmt[i++]);
        continue;
      }

      const std::size_t end = fmt.find('}', i + 1);
      if (end == std::string_view::npos) {
        return std::nullopt;
      }
      const std::string_view field = fmt.substr(i + 1, end - i - 1);
      const std::size_t colon = field.find(':');
      if (colon == std::string_view::npos) {
        return std::nullopt;
      }
      std::string_view spec = field.substr(colon + 1);
      const std::size_t firstPercent = spec.find('%');
      if (firstPercent == std::string_view::npos) {
        return std::nullopt;
      }
      spec.remove_prefix(firstPercent);
      out += strftimeSpec(spec, local);
      formattedField = true;
      i = end + 1;
    }

    if (!formattedField) {
      return std::nullopt;
    }
    return out;
  }

} // namespace

std::string formatLocalTime(const char* fmt) {
  using namespace std::chrono;
  const auto now = floor<seconds>(system_clock::now());
  const std::time_t raw = system_clock::to_time_t(now);
  std::tm localTm{};
  localtime_r(&raw, &localTm);
  if (auto compat = formatStrftimeCompat(fmt, localTm)) {
    return *compat;
  }

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
    return i18n::tr("time.file.unknown");
  }
  const auto systemNow = std::chrono::system_clock::now();
  const auto fileNow = std::filesystem::file_time_type::clock::now();
  const auto systemTime = std::chrono::time_point_cast<std::chrono::system_clock::duration>(time - fileNow + systemNow);
  const std::time_t value = std::chrono::system_clock::to_time_t(systemTime);
  std::tm tm{};
  localtime_r(&value, &tm);
  char buf[32];
  if (std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M", &tm) == 0) {
    return i18n::tr("time.file.unknown");
  }
  return buf;
}

std::string formatTimeAgo(std::chrono::system_clock::time_point tp) {
  using namespace std::chrono;
  const auto secs = duration_cast<seconds>(system_clock::now() - tp).count();

  if (secs < 60) {
    return i18n::tr("time.relative.just-now");
  }
  if (secs < 3600) {
    const long mins = secs / 60;
    return i18n::trp("time.relative.minutes-ago", mins);
  }
  if (secs < 86400) {
    const long hrs = secs / 3600;
    return i18n::trp("time.relative.hours-ago", hrs);
  }
  if (secs < 7 * 86400) {
    const long days = secs / 86400;
    return i18n::trp("time.relative.days-ago", days);
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
    return i18n::tr("time.duration.days-hours-minutes", "days", days, "hours", hours, "minutes", minutes);
  }
  if (hours > 0) {
    return i18n::tr("time.duration.hours-minutes", "hours", hours, "minutes", minutes);
  }
  if (minutes > 0) {
    return i18n::tr("time.duration.minutes", "minutes", minutes);
  }
  return i18n::tr("time.duration.less-than-minute");
}
