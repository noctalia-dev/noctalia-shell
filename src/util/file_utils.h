#pragma once

#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

namespace FileUtils {

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

  [[nodiscard]] inline std::string configDir() {
    const char* xdg = std::getenv("XDG_CONFIG_HOME");
    if (xdg != nullptr && xdg[0] != '\0') {
      return std::string(xdg) + "/noctalia";
    }
    const char* home = std::getenv("HOME");
    if (home != nullptr && home[0] != '\0') {
      return std::string(home) + "/.config/noctalia";
    }
    return {};
  }

  [[nodiscard]] inline std::string stateDir() {
    const char* xdg = std::getenv("XDG_STATE_HOME");
    if (xdg != nullptr && xdg[0] != '\0') {
      return std::string(xdg) + "/noctalia";
    }
    const char* home = std::getenv("HOME");
    if (home != nullptr && home[0] != '\0') {
      return std::string(home) + "/.local/state/noctalia";
    }
    return {};
  }

  [[nodiscard]] inline std::vector<std::uint8_t> readBinaryFile(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) {
      return {};
    }
    const auto size = file.tellg();
    if (size <= 0) {
      return {};
    }
    std::vector<std::uint8_t> data(static_cast<std::size_t>(size));
    file.seekg(0);
    file.read(reinterpret_cast<char*>(data.data()), size);
    if (!file) {
      return {};
    }
    return data;
  }

} // namespace FileUtils
