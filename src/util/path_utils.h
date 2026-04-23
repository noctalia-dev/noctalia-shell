#pragma once

#include <cstdlib>
#include <filesystem>
#include <string>

namespace PathUtils {

  [[nodiscard]] inline std::filesystem::path expandUserPath(const std::string& path) {
    if (path.empty() || path[0] != '~') {
      return std::filesystem::path(path);
    }
    const char* home = std::getenv("HOME");
    if (home == nullptr || home[0] == '\0') {
      return std::filesystem::path(path);
    }
    if (path.size() == 1) {
      return std::filesystem::path(home);
    }
    if (path[1] == '/') {
      return std::filesystem::path(home) / path.substr(2);
    }
    return std::filesystem::path(path);
  }

} // namespace PathUtils
