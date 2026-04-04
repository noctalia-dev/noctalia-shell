#include "config/ConfigService.h"

#include "core/Log.h"
#include "wayland/WaylandConnection.h"

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

std::string configPath() {
  const char* xdg = std::getenv("XDG_CONFIG_HOME");
  if (xdg != nullptr && xdg[0] != '\0') {
    return std::string(xdg) + "/noctalia/config.toml";
  }
  const char* home = std::getenv("HOME");
  if (home != nullptr && home[0] != '\0') {
    return std::string(home) + "/.config/noctalia/config.toml";
  }
  return {};
}

std::vector<std::string> readStringArray(const toml::node& node) {
  std::vector<std::string> result;
  if (auto* arr = node.as_array()) {
    for (const auto& item : *arr) {
      if (auto* str = item.as_string()) {
        result.push_back(str->get());
      }
    }
  }
  return result;
}

bool matchesOutput(const std::string& match, const WaylandOutput& output) {
  // Exact connector name match
  if (!output.connectorName.empty() && match == output.connectorName) {
    return true;
  }
  // Substring match on description
  if (!output.description.empty() && output.description.find(match) != std::string::npos) {
    return true;
  }
  return false;
}

} // namespace

ConfigService::ConfigService() {
  m_configPath = configPath();
  if (!m_configPath.empty() && std::filesystem::exists(m_configPath)) {
    loadFromFile(m_configPath);
  } else {
    logInfo("config: no config file found, using defaults");
    m_config.bars.push_back(BarConfig{});
  }
  setupWatch();
}

ConfigService::~ConfigService() {
  if (m_watchFd >= 0 && m_inotifyFd >= 0) {
    inotify_rm_watch(m_inotifyFd, m_watchFd);
  }
  if (m_inotifyFd >= 0) {
    ::close(m_inotifyFd);
  }
}

void ConfigService::setReloadCallback(ReloadCallback callback) { m_reloadCallback = std::move(callback); }

void ConfigService::checkReload() {
  if (m_inotifyFd < 0) {
    return;
  }

  // Drain inotify events, check if our config file was involved
  alignas(inotify_event) char buf[4096];
  bool configChanged = false;
  const auto configFilename = std::filesystem::path(m_configPath).filename().string();

  while (true) {
    const auto n = ::read(m_inotifyFd, buf, sizeof(buf));
    if (n <= 0) {
      break;
    }

    // Walk through events to check filenames
    std::size_t offset = 0;
    while (offset < static_cast<std::size_t>(n)) {
      auto* event = reinterpret_cast<inotify_event*>(buf + offset);
      if (event->len > 0 && configFilename == event->name) {
        configChanged = true;
      }
      offset += sizeof(inotify_event) + event->len;
    }
  }

  if (!configChanged) {
    return;
  }

  m_config = Config{};
  if (!m_configPath.empty() && std::filesystem::exists(m_configPath)) {
    loadFromFile(m_configPath);
  } else {
    m_config.bars.push_back(BarConfig{});
  }

  if (m_reloadCallback) {
    m_reloadCallback();
  }
}

void ConfigService::setupWatch() {
  if (m_configPath.empty()) {
    return;
  }

  m_inotifyFd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (m_inotifyFd < 0) {
    logWarn("config: inotify_init1 failed, hot reload disabled");
    return;
  }

  // Watch the directory (not just the file) to catch editors that rename+create
  auto dir = std::filesystem::path(m_configPath).parent_path().string();
  m_watchFd = inotify_add_watch(m_inotifyFd, dir.c_str(), IN_MODIFY | IN_CREATE | IN_MOVED_TO);
  if (m_watchFd < 0) {
    logWarn("config: inotify_add_watch failed, hot reload disabled");
    ::close(m_inotifyFd);
    m_inotifyFd = -1;
    return;
  }

  logDebug("config: watching {} for changes", dir);
}

void ConfigService::loadFromFile(const std::string& path) {
  logInfo("config: loading {}", path);

  toml::table tbl;
  try {
    tbl = toml::parse_file(path);
  } catch (const toml::parse_error& e) {
    logWarn("config: parse error: {}", e.what());
    m_config.bars.push_back(BarConfig{});
    return;
  }

  // Parse [[bar]] array
  if (auto* barArray = tbl["bar"].as_array()) {
    for (const auto& barNode : *barArray) {
      auto* barTbl = barNode.as_table();
      if (barTbl == nullptr) {
        continue;
      }

      BarConfig bar;
      if (auto v = (*barTbl)["name"].value<std::string>())
        bar.name = *v;
      if (auto v = (*barTbl)["position"].value<std::string>())
        bar.position = *v;
      if (auto v = (*barTbl)["enabled"].value<bool>())
        bar.enabled = *v;
      if (auto v = (*barTbl)["height"].value<int64_t>())
        bar.height = static_cast<std::uint32_t>(*v);
      if (auto v = (*barTbl)["padding"].value<double>())
        bar.padding = static_cast<float>(*v);
      if (auto v = (*barTbl)["gap"].value<double>())
        bar.gap = static_cast<float>(*v);
      if (auto* n = (*barTbl)["start"].as_array())
        bar.startWidgets = readStringArray(*n);
      if (auto* n = (*barTbl)["center"].as_array())
        bar.centerWidgets = readStringArray(*n);
      if (auto* n = (*barTbl)["end"].as_array())
        bar.endWidgets = readStringArray(*n);

      // Parse [[bar.monitor]] overrides
      if (auto* monArray = (*barTbl)["monitor"].as_array()) {
        for (const auto& monNode : *monArray) {
          auto* monTbl = monNode.as_table();
          if (monTbl == nullptr) {
            continue;
          }

          BarMonitorOverride ovr;
          if (auto v = (*monTbl)["match"].value<std::string>()) {
            ovr.match = *v;
          } else {
            continue; // match is required
          }

          if (auto v = (*monTbl)["enabled"].value<bool>())
            ovr.enabled = *v;
          if (auto v = (*monTbl)["height"].value<int64_t>())
            ovr.height = static_cast<std::uint32_t>(*v);
          if (auto v = (*monTbl)["padding"].value<double>())
            ovr.padding = static_cast<float>(*v);
          if (auto v = (*monTbl)["gap"].value<double>())
            ovr.gap = static_cast<float>(*v);
          if (auto* n = (*monTbl)["start"].as_array())
            ovr.startWidgets = readStringArray(*n);
          if (auto* n = (*monTbl)["center"].as_array())
            ovr.centerWidgets = readStringArray(*n);
          if (auto* n = (*monTbl)["end"].as_array())
            ovr.endWidgets = readStringArray(*n);

          bar.monitorOverrides.push_back(std::move(ovr));
        }
      }

      m_config.bars.push_back(std::move(bar));
    }
  }

  // Parse [clock]
  if (auto* clockTbl = tbl["clock"].as_table()) {
    if (auto v = (*clockTbl)["format"].value<std::string>()) {
      m_config.clock.format = *v;
    }
  }

  // Parse [wallpaper]
  if (auto* wpTbl = tbl["wallpaper"].as_table()) {
    auto& wp = m_config.wallpaper;
    if (auto v = (*wpTbl)["enabled"].value<bool>())
      wp.enabled = *v;
    if (auto v = (*wpTbl)["fill_mode"].value<std::string>()) {
      if (*v == "center")
        wp.fillMode = WallpaperFillMode::Center;
      else if (*v == "crop")
        wp.fillMode = WallpaperFillMode::Crop;
      else if (*v == "fit")
        wp.fillMode = WallpaperFillMode::Fit;
      else if (*v == "stretch")
        wp.fillMode = WallpaperFillMode::Stretch;
      else if (*v == "repeat")
        wp.fillMode = WallpaperFillMode::Repeat;
    }
    if (auto v = (*wpTbl)["transition"].value<std::string>()) {
      if (*v == "fade")
        wp.transition = WallpaperTransition::Fade;
      else if (*v == "wipe")
        wp.transition = WallpaperTransition::Wipe;
      else if (*v == "disc")
        wp.transition = WallpaperTransition::Disc;
      else if (*v == "stripes")
        wp.transition = WallpaperTransition::Stripes;
      else if (*v == "pixelate")
        wp.transition = WallpaperTransition::Pixelate;
      else if (*v == "honeycomb")
        wp.transition = WallpaperTransition::Honeycomb;
    }
    if (auto v = (*wpTbl)["transition_duration"].value<double>())
      wp.transitionDurationMs = static_cast<float>(*v);
    if (auto v = (*wpTbl)["edge_smoothness"].value<double>())
      wp.edgeSmoothness = static_cast<float>(*v);
  }

  if (m_config.bars.empty()) {
    logInfo("config: no [[bar]] defined, using defaults");
    m_config.bars.push_back(BarConfig{});
  }

  logInfo("config: {} bar(s) defined", m_config.bars.size());
}

BarConfig ConfigService::resolveForOutput(const BarConfig& base, const WaylandOutput& output) {
  BarConfig resolved = base;

  for (const auto& ovr : base.monitorOverrides) {
    if (!matchesOutput(ovr.match, output)) {
      continue;
    }

    logDebug("config: monitor override \"{}\" matched output {} ({})", ovr.match, output.connectorName,
             output.description);

    if (ovr.enabled)
      resolved.enabled = *ovr.enabled;
    if (ovr.height)
      resolved.height = *ovr.height;
    if (ovr.padding)
      resolved.padding = *ovr.padding;
    if (ovr.gap)
      resolved.gap = *ovr.gap;
    if (ovr.startWidgets)
      resolved.startWidgets = *ovr.startWidgets;
    if (ovr.centerWidgets)
      resolved.centerWidgets = *ovr.centerWidgets;
    if (ovr.endWidgets)
      resolved.endWidgets = *ovr.endWidgets;
    break; // first match wins
  }

  return resolved;
}
