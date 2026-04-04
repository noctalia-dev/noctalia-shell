#include "config/StateService.h"

#include "core/Log.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#include <toml.hpp>
#pragma GCC diagnostic pop

#include <cstdlib>
#include <filesystem>
#include <sys/inotify.h>
#include <unistd.h>

namespace {

std::string statePath() {
  const char* xdg = std::getenv("XDG_STATE_HOME");
  if (xdg != nullptr && xdg[0] != '\0') {
    return std::string(xdg) + "/noctalia/state.toml";
  }
  const char* home = std::getenv("HOME");
  if (home != nullptr && home[0] != '\0') {
    return std::string(home) + "/.local/state/noctalia/state.toml";
  }
  return {};
}

} // namespace

StateService::StateService() {
  m_statePath = statePath();
  if (!m_statePath.empty()) {
    // Create directory if it doesn't exist
    auto dir = std::filesystem::path(m_statePath).parent_path();
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);

    if (std::filesystem::exists(m_statePath)) {
      loadFromFile(m_statePath);
    } else {
      logInfo("state: no state file found at {}", m_statePath);
    }
  }
  setupWatch();
}

StateService::~StateService() {
  if (m_watchDescriptor >= 0 && m_inotifyFd >= 0) {
    inotify_rm_watch(m_inotifyFd, m_watchDescriptor);
  }
  if (m_inotifyFd >= 0) {
    ::close(m_inotifyFd);
  }
}

std::string StateService::getWallpaperPath(const std::string& connectorName) const {
  auto it = m_monitorWallpaperPaths.find(connectorName);
  if (it != m_monitorWallpaperPaths.end()) {
    return it->second;
  }
  return m_defaultWallpaperPath;
}

std::string StateService::getDefaultWallpaperPath() const { return m_defaultWallpaperPath; }

void StateService::setWallpaperChangeCallback(ChangeCallback callback) {
  m_wallpaperChangeCallback = std::move(callback);
}

void StateService::checkReload() {
  if (m_inotifyFd < 0) {
    return;
  }

  alignas(inotify_event) char buf[4096];
  bool stateChanged = false;
  const auto stateFilename = std::filesystem::path(m_statePath).filename().string();

  while (true) {
    const auto n = ::read(m_inotifyFd, buf, sizeof(buf));
    if (n <= 0) {
      break;
    }

    std::size_t offset = 0;
    while (offset < static_cast<std::size_t>(n)) {
      auto* event = reinterpret_cast<inotify_event*>(buf + offset);
      if (event->len > 0 && stateFilename == event->name) {
        stateChanged = true;
      }
      offset += sizeof(inotify_event) + event->len;
    }
  }

  if (!stateChanged) {
    return;
  }

  logInfo("state: reloading {}", m_statePath);

  auto oldDefault = m_defaultWallpaperPath;
  auto oldMonitors = m_monitorWallpaperPaths;

  m_defaultWallpaperPath.clear();
  m_monitorWallpaperPaths.clear();

  if (std::filesystem::exists(m_statePath)) {
    loadFromFile(m_statePath);
  }

  // Check if wallpaper data actually changed
  bool wallpaperChanged = (oldDefault != m_defaultWallpaperPath || oldMonitors != m_monitorWallpaperPaths);
  if (wallpaperChanged && m_wallpaperChangeCallback) {
    m_wallpaperChangeCallback();
  }
}

void StateService::setupWatch() {
  if (m_statePath.empty()) {
    return;
  }

  m_inotifyFd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (m_inotifyFd < 0) {
    logWarn("state: inotify_init1 failed, state file watch disabled");
    return;
  }

  auto dir = std::filesystem::path(m_statePath).parent_path().string();
  m_watchDescriptor = inotify_add_watch(m_inotifyFd, dir.c_str(), IN_MODIFY | IN_CREATE | IN_MOVED_TO);
  if (m_watchDescriptor < 0) {
    logWarn("state: inotify_add_watch failed, state file watch disabled");
    ::close(m_inotifyFd);
    m_inotifyFd = -1;
    return;
  }

  logDebug("state: watching {} for changes", dir);
}

void StateService::loadFromFile(const std::string& path) {
  logInfo("state: loading {}", path);

  toml::table tbl;
  try {
    tbl = toml::parse_file(path);
  } catch (const toml::parse_error& e) {
    logWarn("state: parse error: {}", e.what());
    return;
  }

  // Parse [wallpaper.default]
  if (auto* wpDefault = tbl["wallpaper"]["default"].as_table()) {
    if (auto v = (*wpDefault)["path"].value<std::string>()) {
      m_defaultWallpaperPath = *v;
    }
  }

  // Parse [wallpaper.monitors."connector-name"]
  if (auto* monitors = tbl["wallpaper"]["monitors"].as_table()) {
    for (const auto& [key, value] : *monitors) {
      if (auto* monTbl = value.as_table()) {
        if (auto v = (*monTbl)["path"].value<std::string>()) {
          m_monitorWallpaperPaths[std::string(key.str())] = *v;
        }
      }
    }
  }

  logInfo("state: wallpaper default=\"{}\" monitors={}", m_defaultWallpaperPath, m_monitorWallpaperPaths.size());
}
