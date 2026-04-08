#include "system/distro_info.h"

#include <cctype>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>
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
