#include "system/distro_info.h"

#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <ctime>
#include <fcntl.h>
#include <filesystem>
#include <format>
#include <fstream>
#include <pwd.h>
#include <string>
#include <string_view>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>
#include <unordered_map>

namespace {

  std::string trim(std::string_view value) {
    std::size_t start = 0;
    while (start < value.size() && std::isspace(static_cast<unsigned char>(value[start])) != 0) {
      ++start;
    }

    std::size_t end = value.size();
    while (end > start && std::isspace(static_cast<unsigned char>(value[end - 1])) != 0) {
      --end;
    }

    return std::string(value.substr(start, end - start));
  }

  std::string unquote(std::string value) {
    if (value.size() >= 2 &&
        ((value.front() == '"' && value.back() == '"') || (value.front() == '\'' && value.back() == '\''))) {
      value = value.substr(1, value.size() - 2);
    }

    std::string out;
    out.reserve(value.size());
    bool escaping = false;
    for (char ch : value) {
      if (escaping) {
        out.push_back(ch);
        escaping = false;
        continue;
      }
      if (ch == '\\') {
        escaping = true;
        continue;
      }
      out.push_back(ch);
    }
    return out;
  }

  std::optional<std::unordered_map<std::string, std::string>> parseOsRelease(const std::filesystem::path& path) {
    std::ifstream file(path);
    if (!file.is_open()) {
      return std::nullopt;
    }

    std::unordered_map<std::string, std::string> values;
    std::string line;
    while (std::getline(file, line)) {
      const auto trimmed = trim(line);
      if (trimmed.empty() || trimmed.front() == '#') {
        continue;
      }

      const auto eq = trimmed.find('=');
      if (eq == std::string::npos || eq == 0) {
        continue;
      }

      auto key = std::string(trimmed.substr(0, eq));
      auto value = unquote(trim(std::string_view(trimmed).substr(eq + 1)));
      values[std::move(key)] = std::move(value);
    }

    return values;
  }

} // namespace

std::optional<DistroInfo> DistroDetector::detect() {
  const std::filesystem::path candidates[] = {"/etc/os-release", "/usr/lib/os-release"};

  for (const auto& path : candidates) {
    const auto parsed = parseOsRelease(path);
    if (!parsed.has_value()) {
      continue;
    }

    DistroInfo info;
    if (const auto it = parsed->find("ID"); it != parsed->end()) {
      info.id = it->second;
    }
    if (const auto it = parsed->find("NAME"); it != parsed->end()) {
      info.name = it->second;
    }
    if (const auto it = parsed->find("VERSION"); it != parsed->end()) {
      info.version = it->second;
    }
    if (const auto it = parsed->find("PRETTY_NAME"); it != parsed->end()) {
      info.prettyName = it->second;
    }

    if (!info.prettyName.empty() || !info.name.empty() || !info.id.empty()) {
      return info;
    }
  }

  return std::nullopt;
}

std::string distroLabel() {
  if (const auto distro = DistroDetector::detect(); distro.has_value()) {
    if (!distro->prettyName.empty()) {
      return distro->prettyName;
    }
    if (!distro->name.empty()) {
      return distro->name;
    }
    if (!distro->id.empty()) {
      return distro->id;
    }
  }
  return "Unknown distro";
}

std::string kernelRelease() {
  struct utsname un{};
  if (uname(&un) == 0 && un.release[0] != '\0') {
    return un.release;
  }
  return "unknown";
}

std::string osAgeLabel() {
  std::uint64_t oldest = 0;

  for (const char* path : {"/", "/etc", "/var", "/home"}) {
    struct statx sx{};
    if (statx(AT_FDCWD, path, AT_SYMLINK_NOFOLLOW, STATX_BTIME, &sx) == 0 && (sx.stx_mask & STATX_BTIME) != 0 &&
        sx.stx_btime.tv_sec > 0) {
      const std::uint64_t birth = static_cast<std::uint64_t>(sx.stx_btime.tv_sec);
      if (oldest == 0 || birth < oldest) {
        oldest = birth;
      }
    }
  }

  if (oldest == 0) {
    struct stat st{};
    if (stat("/etc/machine-id", &st) == 0 && st.st_mtime > 0) {
      oldest = static_cast<std::uint64_t>(st.st_mtime);
    }
  }

  if (oldest == 0) {
    return "unknown";
  }
  const std::time_t now = std::time(nullptr);
  if (now <= 0 || static_cast<std::uint64_t>(now) <= oldest) {
    return "<1d";
  }

  const std::uint64_t seconds = static_cast<std::uint64_t>(now) - oldest;
  const std::uint64_t days = seconds / 86400;
  const std::uint64_t years = days / 365;
  const std::uint64_t months = (days % 365) / 30;
  if (years > 0) {
    if (months > 0) {
      return std::format("{}y {}mo", years, months);
    }
    return std::format("{}y", years);
  }
  return std::format("{}d", days);
}

std::string sessionDisplayName() {
  struct passwd* pw = getpwuid(getuid());
  const char* loginEnv = std::getenv("USER");
  std::string login = "user";
  if (pw != nullptr) {
    login = pw->pw_name;
  } else if (loginEnv != nullptr) {
    login = loginEnv;
  }

  if (pw != nullptr && pw->pw_gecos != nullptr && pw->pw_gecos[0] != '\0') {
    std::string gecos = pw->pw_gecos;
    const auto comma = gecos.find(',');
    return comma == std::string::npos ? gecos : gecos.substr(0, comma);
  }
  return login;
}
