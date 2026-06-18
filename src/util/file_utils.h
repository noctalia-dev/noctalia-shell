#pragma once

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <optional>
#include <string>
#include <string_view>
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

  [[nodiscard]] inline std::string expandUserPathString(const std::string& path) {
    return expandUserPath(path).string();
  }

  [[nodiscard]] inline bool
  containsPath(const std::vector<std::filesystem::path>& paths, const std::filesystem::path& path) {
    return std::ranges::contains(paths, path);
  }

  [[nodiscard]] inline std::optional<std::string> readSmallTextFile(const std::filesystem::path& path) {
    std::ifstream file{path};
    if (!file.is_open()) {
      return std::nullopt;
    }

    std::string text;
    std::getline(file, text);
    if (text.empty()) {
      return std::nullopt;
    }

    while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ' || text.back() == '\t')) {
      text.pop_back();
    }
    return text;
  }

  [[nodiscard]] inline std::string configDir() {
    const char* noctalia = std::getenv("NOCTALIA_CONFIG_HOME");
    if (noctalia != nullptr && noctalia[0] != '\0') {
      return std::string(noctalia) + "/noctalia";
    }
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
    const char* noctalia = std::getenv("NOCTALIA_STATE_HOME");
    if (noctalia != nullptr && noctalia[0] != '\0') {
      return std::string(noctalia) + "/noctalia";
    }
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

  [[nodiscard]] inline std::string dataDir() {
    const char* noctalia = std::getenv("NOCTALIA_DATA_HOME");
    if (noctalia != nullptr && noctalia[0] != '\0') {
      return std::string(noctalia) + "/noctalia";
    }
    const char* xdg = std::getenv("XDG_DATA_HOME");
    if (xdg != nullptr && xdg[0] != '\0') {
      return std::string(xdg) + "/noctalia";
    }
    const char* home = std::getenv("HOME");
    if (home != nullptr && home[0] != '\0') {
      return std::string(home) + "/.local/share/noctalia";
    }
    return {};
  }

  // Git-source repo caches. Host-managed, re-fetchable, so they live under the
  // state dir — never config.
  [[nodiscard]] inline std::string pluginSourcesDir() {
    const std::string base = stateDir();
    if (base.empty()) {
      return {};
    }
    return base + "/plugins/sources";
  }

  // Exported runtime files for enabled git-source plugins. Re-derivable from
  // source repos; path sources and local dev plugins do not use this directory.
  [[nodiscard]] inline std::string pluginMaterializedDir() {
    const std::string base = stateDir();
    if (base.empty()) {
      return {};
    }
    return base + "/plugins/materialized";
  }

  [[nodiscard]] inline std::vector<std::uint8_t> readBinaryFile(const std::string& path) {
    if (path.empty()) {
      return {};
    }

    std::error_code ec;
    const std::filesystem::path fsPath = expandUserPath(path);
    if (!std::filesystem::is_regular_file(fsPath, ec) || ec) {
      return {};
    }

    const std::uintmax_t fileSize = std::filesystem::file_size(fsPath, ec);
    if (ec || fileSize == 0) {
      return {};
    }

    constexpr std::uintmax_t kMaxBinaryReadBytes = 256ULL * 1024ULL * 1024ULL;
    if (fileSize > kMaxBinaryReadBytes) {
      return {};
    }

    std::ifstream file(fsPath, std::ios::binary);
    if (!file) {
      return {};
    }

    std::vector<std::uint8_t> data(static_cast<std::size_t>(fileSize));
    file.read(reinterpret_cast<char*>(data.data()), static_cast<std::streamsize>(fileSize));
    if (!file) {
      return {};
    }
    return data;
  }

  // Expands ~ and resolves relative paths against baseDir when provided; otherwise uses the
  // process working directory for relative paths.
  [[nodiscard]] inline std::filesystem::path
  resolvePath(std::string_view path, std::optional<std::string_view> baseDir = std::nullopt) {
    if (path.empty() || path.starts_with("color:")) {
      return std::filesystem::path(path);
    }

    std::filesystem::path resolved = expandUserPath(std::string(path));
    if (!resolved.is_absolute()) {
      if (baseDir.has_value() && !baseDir->empty()) {
        resolved = std::filesystem::path(*baseDir) / resolved;
      } else {
        std::error_code ec;
        resolved = std::filesystem::absolute(resolved, ec);
        if (ec) {
          return std::filesystem::path(path);
        }
      }
    }

    std::error_code ec;
    return resolved.lexically_normal();
  }

  [[nodiscard]] inline std::string normalizeWallpaperPath(std::string_view path) {
    if (path.empty() || path.starts_with("color:")) {
      return std::string(path);
    }

    std::error_code ec;
    auto absolute = std::filesystem::absolute(std::filesystem::path(path), ec);
    if (ec) {
      absolute = std::filesystem::path(path);
    }
    return expandUserPath(absolute.lexically_normal().string()).string();
  }

} // namespace FileUtils
