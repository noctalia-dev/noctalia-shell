#include "config/state_service.h"

#include "core/log.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#include <toml.hpp>
#pragma GCC diagnostic pop

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
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

  constexpr Logger kLog("state");

} // namespace

StateService::WallpaperBatch::WallpaperBatch(StateService& state) : m_state(state) { ++m_state.m_batchDepth; }

StateService::WallpaperBatch::~WallpaperBatch() {
  --m_state.m_batchDepth;
  if (m_state.m_batchDepth == 0 && m_state.m_batchDirty) {
    m_state.m_batchDirty = false;
    if (m_state.m_wallpaperChangeCallback) {
      m_state.m_wallpaperChangeCallback();
    }
  }
}

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
      kLog.info("no state file found at {}", m_statePath);
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

void StateService::setWallpaperPath(const std::optional<std::string>& connectorName, const std::string& path) {
  if (m_statePath.empty()) {
    return;
  }

  bool changed = false;
  if (connectorName.has_value()) {
    auto it = m_monitorWallpaperPaths.find(*connectorName);
    if (it == m_monitorWallpaperPaths.end() || it->second != path) {
      m_monitorWallpaperPaths[*connectorName] = path;
      changed = true;
    }
  } else {
    if (m_defaultWallpaperPath != path) {
      m_defaultWallpaperPath = path;
      changed = true;
    }
  }

  if (!changed) {
    return;
  }

  if (!writeToFile()) {
    kLog.warn("failed to write {}", m_statePath);
    return;
  }

  m_ownWritePending = true;
  if (m_batchDepth > 0) {
    m_batchDirty = true;
    return;
  }
  if (m_wallpaperChangeCallback) {
    m_wallpaperChangeCallback();
  }
}

bool StateService::writeToFile() const {
  toml::table root;

  toml::table wallpaperTbl;
  toml::table defaultTbl;
  defaultTbl.insert("path", m_defaultWallpaperPath);
  wallpaperTbl.insert("default", std::move(defaultTbl));

  if (!m_monitorWallpaperPaths.empty()) {
    toml::table monitorsTbl;
    for (const auto& [connector, monPath] : m_monitorWallpaperPaths) {
      toml::table monTbl;
      monTbl.insert("path", monPath);
      monitorsTbl.insert(connector, std::move(monTbl));
    }
    wallpaperTbl.insert("monitors", std::move(monitorsTbl));
  }

  root.insert("wallpaper", std::move(wallpaperTbl));

  const std::string tmpPath = m_statePath + ".tmp";
  {
    std::ofstream out(tmpPath, std::ios::trunc);
    if (!out.is_open()) {
      return false;
    }
    out << root;
    if (!out.good()) {
      return false;
    }
  }

  std::error_code ec;
  std::filesystem::rename(tmpPath, m_statePath, ec);
  if (ec) {
    std::filesystem::remove(tmpPath, ec);
    return false;
  }
  return true;
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

  if (m_ownWritePending) {
    m_ownWritePending = false;
    return;
  }

  kLog.info("reloading {}", m_statePath);

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
    kLog.warn("inotify_init1 failed, state file watch disabled");
    return;
  }

  auto dir = std::filesystem::path(m_statePath).parent_path().string();
  m_watchDescriptor = inotify_add_watch(m_inotifyFd, dir.c_str(), IN_MODIFY | IN_CREATE | IN_MOVED_TO);
  if (m_watchDescriptor < 0) {
    kLog.warn("inotify_add_watch failed, state file watch disabled");
    ::close(m_inotifyFd);
    m_inotifyFd = -1;
    return;
  }

  kLog.debug("watching {} for changes", dir);
}

void StateService::loadFromFile(const std::string& path) {
  kLog.info("loading {}", path);

  toml::table tbl;
  try {
    tbl = toml::parse_file(path);
  } catch (const toml::parse_error& e) {
    kLog.warn("parse error: {}", e.what());
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

  kLog.info("wallpaper default=\"{}\" monitors={}", m_defaultWallpaperPath, m_monitorWallpaperPaths.size());
}
