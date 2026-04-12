#include "config/config_service.h"

#include "core/log.h"
#include "notification/notification_manager.h"
#include "wayland/wayland_connection.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#include <toml.hpp>
#pragma GCC diagnostic pop

#include <algorithm>
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

  constexpr Logger kLog("config");

} // namespace

// ── Lifecycle ────────────────────────────────────────────────────────────────

ConfigService::ConfigService() {
  m_configPath = configPath();
  if (!m_configPath.empty() && std::filesystem::exists(m_configPath)) {
    loadFromFile(m_configPath);
  } else {
    kLog.info("no config file found, using defaults");
    seedBuiltinWidgets(m_config);
    m_config.idle.behaviors.push_back(IdleBehaviorConfig{
        .name = "lock",
        .enabled = false,
        .timeoutSeconds = 660,
        .command = "noctalia:lock",
    });
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

// ── Public interface ─────────────────────────────────────────────────────────

void ConfigService::addReloadCallback(ReloadCallback callback) { m_reloadCallbacks.push_back(std::move(callback)); }

void ConfigService::setNotificationManager(NotificationManager* manager) {
  m_notificationManager = manager;
  if (m_notificationManager != nullptr && !m_pendingError.empty()) {
    m_configErrorNotificationId =
        m_notificationManager->addInternal("Noctalia", "Config parse error", m_pendingError, Urgency::Critical, 0);
    m_pendingError.clear();
  }
}

void ConfigService::forceReload() {
  m_config = Config{};
  if (!m_configPath.empty() && std::filesystem::exists(m_configPath)) {
    loadFromFile(m_configPath);
  } else {
    seedBuiltinWidgets(m_config);
    m_config.idle.behaviors.push_back(IdleBehaviorConfig{
        .name = "lock",
        .enabled = false,
        .timeoutSeconds = 660,
        .command = "noctalia:lock",
    });
    m_config.bars.push_back(BarConfig{});
  }
  for (const auto& cb : m_reloadCallbacks) {
    cb();
  }
}

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

  kLog.info("config changed, reloading");
  m_config = Config{};
  if (!m_configPath.empty() && std::filesystem::exists(m_configPath)) {
    loadFromFile(m_configPath);
  } else {
    seedBuiltinWidgets(m_config);
    m_config.idle.behaviors.push_back(IdleBehaviorConfig{
        .name = "lock",
        .enabled = false,
        .timeoutSeconds = 660,
        .command = "noctalia:lock",
    });
    m_config.bars.push_back(BarConfig{});
  }

  for (const auto& cb : m_reloadCallbacks) {
    cb();
  }
}

BarConfig ConfigService::resolveForOutput(const BarConfig& base, const WaylandOutput& output) {
  BarConfig resolved = base;

  for (const auto& ovr : base.monitorOverrides) {
    if (!matchesOutput(ovr.match, output)) {
      continue;
    }

    kLog.debug("monitor override \"{}\" matched output {} ({})", ovr.match, output.connectorName, output.description);

    if (ovr.enabled)
      resolved.enabled = *ovr.enabled;
    if (ovr.height)
      resolved.height = *ovr.height;
    if (ovr.backgroundOpacity)
      resolved.backgroundOpacity = *ovr.backgroundOpacity;
    if (ovr.radius) {
      resolved.radius = *ovr.radius;
      resolved.radiusTopLeft = *ovr.radius;
      resolved.radiusTopRight = *ovr.radius;
      resolved.radiusBottomLeft = *ovr.radius;
      resolved.radiusBottomRight = *ovr.radius;
    }
    if (ovr.radiusTopLeft)
      resolved.radiusTopLeft = *ovr.radiusTopLeft;
    if (ovr.radiusTopRight)
      resolved.radiusTopRight = *ovr.radiusTopRight;
    if (ovr.radiusBottomLeft)
      resolved.radiusBottomLeft = *ovr.radiusBottomLeft;
    if (ovr.radiusBottomRight)
      resolved.radiusBottomRight = *ovr.radiusBottomRight;
    if (ovr.marginH)
      resolved.marginH = *ovr.marginH;
    if (ovr.marginV)
      resolved.marginV = *ovr.marginV;
    if (ovr.paddingH)
      resolved.paddingH = *ovr.paddingH;
    if (ovr.widgetSpacing)
      resolved.widgetSpacing = *ovr.widgetSpacing;
    if (ovr.shadowBlur)
      resolved.shadowBlur = *ovr.shadowBlur;
    if (ovr.shadowOffsetX)
      resolved.shadowOffsetX = *ovr.shadowOffsetX;
    if (ovr.shadowOffsetY)
      resolved.shadowOffsetY = *ovr.shadowOffsetY;
    if (ovr.startWidgets)
      resolved.startWidgets = *ovr.startWidgets;
    if (ovr.centerWidgets)
      resolved.centerWidgets = *ovr.centerWidgets;
    if (ovr.endWidgets)
      resolved.endWidgets = *ovr.endWidgets;
    if (ovr.scale)
      resolved.scale = *ovr.scale;
    break; // first match wins
  }

  return resolved;
}

// ── Private helpers ──────────────────────────────────────────────────────────

void ConfigService::setupWatch() {
  if (m_configPath.empty()) {
    return;
  }

  m_inotifyFd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (m_inotifyFd < 0) {
    kLog.warn("inotify_init1 failed, hot reload disabled");
    return;
  }

  // Watch the directory (not just the file) to catch editors that rename+create
  auto dir = std::filesystem::path(m_configPath).parent_path().string();
  m_watchFd = inotify_add_watch(m_inotifyFd, dir.c_str(), IN_MODIFY | IN_CREATE | IN_MOVED_TO);
  if (m_watchFd < 0) {
    kLog.warn("inotify_add_watch failed, hot reload disabled");
    ::close(m_inotifyFd);
    m_inotifyFd = -1;
    return;
  }

  kLog.debug("watching {} for changes", dir);
}

void ConfigService::seedBuiltinWidgets(Config& config) {
  // Built-in named widget instances — act as defaults that [widget.*] entries override.
  auto seed = [&](const char* name, WidgetConfig wc) { config.widgets.emplace(name, std::move(wc)); };

  WidgetConfig cpu;
  cpu.type = "sysmon";
  cpu.settings["stat"] = std::string("cpu_usage");
  seed("cpu", std::move(cpu));

  WidgetConfig temp;
  temp.type = "sysmon";
  temp.settings["stat"] = std::string("cpu_temp");
  seed("temp", std::move(temp));

  WidgetConfig ram;
  ram.type = "sysmon";
  ram.settings["stat"] = std::string("ram_used");
  seed("ram", std::move(ram));

  WidgetConfig date;
  date.type = "clock";
  date.settings["format"] = std::string("{:%a %d %b}");
  seed("date", std::move(date));

  WidgetConfig media;
  media.type = "media";
  media.settings["max_length"] = 200.0;
  media.settings["art_size"] = 24.0;
  seed("media", std::move(media));

  WidgetConfig spacer;
  spacer.type = "spacer";
  seed("spacer", std::move(spacer));
}

void ConfigService::loadFromFile(const std::string& path) {
  kLog.info("loading {}", path);

  // Seed built-in named widget instances before parsing so [widget.*] entries override them.
  seedBuiltinWidgets(m_config);

  toml::table tbl;
  try {
    tbl = toml::parse_file(path);
    // Parse succeeded — dismiss any previous config-error notification.
    if (m_notificationManager != nullptr && m_configErrorNotificationId != 0) {
      m_notificationManager->close(m_configErrorNotificationId);
      m_configErrorNotificationId = 0;
    }
    m_pendingError.clear();
  } catch (const toml::parse_error& e) {
    const auto& src = e.source();
    kLog.warn("parse error at line {}, column {}: {}", src.begin.line, src.begin.column, e.description());
    const auto body = std::format("Line {}, column {}: {}", src.begin.line, src.begin.column, e.description());
    if (m_notificationManager != nullptr) {
      // Close previous error notification (if any) so they don't stack on repeated failing reloads.
      if (m_configErrorNotificationId != 0) {
        m_notificationManager->close(m_configErrorNotificationId);
      }
      m_configErrorNotificationId =
          m_notificationManager->addInternal("Noctalia", "Config parse error", body, Urgency::Critical, 0);
    } else {
      m_pendingError = body;
    }
    m_config.bars.push_back(BarConfig{});
    return;
  }

  // Parse [bar.*] named subtables
  if (auto* barTblMap = tbl["bar"].as_table()) {
    for (const auto& [barName, barNode] : *barTblMap) {
      auto* barTbl = barNode.as_table();
      if (barTbl == nullptr) {
        continue;
      }

      BarConfig bar;
      bar.name = std::string(barName.str());
      if (auto v = (*barTbl)["position"].value<std::string>())
        bar.position = *v;
      if (auto v = (*barTbl)["enabled"].value<bool>())
        bar.enabled = *v;
      if (auto v = (*barTbl)["height"].value<int64_t>())
        bar.height = std::clamp(static_cast<std::int32_t>(*v), 10, 300);
      if (auto v = (*barTbl)["background_opacity"].value<double>())
        bar.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
      if (auto v = (*barTbl)["radius"].value<int64_t>()) {
        const auto r = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
        bar.radius = r;
        bar.radiusTopLeft = r;
        bar.radiusTopRight = r;
        bar.radiusBottomLeft = r;
        bar.radiusBottomRight = r;
      }
      if (auto v = (*barTbl)["radius_top_left"].value<int64_t>())
        bar.radiusTopLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["radius_top_right"].value<int64_t>())
        bar.radiusTopRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["radius_bottom_left"].value<int64_t>())
        bar.radiusBottomLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["radius_bottom_right"].value<int64_t>())
        bar.radiusBottomRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["margin_h"].value<int64_t>())
        bar.marginH = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["margin_v"].value<int64_t>())
        bar.marginV = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["padding_h"].value<int64_t>())
        bar.paddingH = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["widget_spacing"].value<int64_t>())
        bar.widgetSpacing = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["shadow_blur"].value<int64_t>())
        bar.shadowBlur = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
      if (auto v = (*barTbl)["shadow_offset_x"].value<int64_t>())
        bar.shadowOffsetX = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
      if (auto v = (*barTbl)["shadow_offset_y"].value<int64_t>())
        bar.shadowOffsetY = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
      if (auto v = (*barTbl)["scale"].value<double>())
        bar.scale = std::clamp(static_cast<float>(*v), 0.5f, 4.0f);
      if (auto* n = (*barTbl)["start"].as_array())
        bar.startWidgets = readStringArray(*n);
      if (auto* n = (*barTbl)["center"].as_array())
        bar.centerWidgets = readStringArray(*n);
      if (auto* n = (*barTbl)["end"].as_array())
        bar.endWidgets = readStringArray(*n);

      // Parse [bar.<name>.monitor.*] overrides — insertion order preserved by toml++
      if (auto* monTblMap = (*barTbl)["monitor"].as_table()) {
        for (const auto& [monName, monNode] : *monTblMap) {
          auto* monTbl = monNode.as_table();
          if (monTbl == nullptr) {
            continue;
          }

          BarMonitorOverride ovr;
          if (auto v = (*monTbl)["match"].value<std::string>()) {
            ovr.match = *v;
          } else {
            ovr.match = std::string(monName.str()); // key is the match if not explicit
          }

          if (auto v = (*monTbl)["enabled"].value<bool>())
            ovr.enabled = *v;
          if (auto v = (*monTbl)["height"].value<int64_t>())
            ovr.height = std::clamp(static_cast<std::int32_t>(*v), 10, 300);
          if (auto v = (*monTbl)["background_opacity"].value<double>())
            ovr.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
          if (auto v = (*monTbl)["radius"].value<int64_t>())
            ovr.radius = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_top_left"].value<int64_t>())
            ovr.radiusTopLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_top_right"].value<int64_t>())
            ovr.radiusTopRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_bottom_left"].value<int64_t>())
            ovr.radiusBottomLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_bottom_right"].value<int64_t>())
            ovr.radiusBottomRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["margin_h"].value<int64_t>())
            ovr.marginH = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["margin_v"].value<int64_t>())
            ovr.marginV = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["padding_h"].value<int64_t>())
            ovr.paddingH = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["widget_spacing"].value<int64_t>())
            ovr.widgetSpacing = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["scale"].value<double>())
            ovr.scale = std::clamp(static_cast<float>(*v), 0.5f, 4.0f);
          if (auto v = (*monTbl)["shadow_blur"].value<int64_t>())
            ovr.shadowBlur = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
          if (auto v = (*monTbl)["shadow_offset_x"].value<int64_t>())
            ovr.shadowOffsetX = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
          if (auto v = (*monTbl)["shadow_offset_y"].value<int64_t>())
            ovr.shadowOffsetY = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
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

  // Parse [widget.*] — named widget instances with per-widget settings
  if (auto* widgetTbl = tbl["widget"].as_table()) {
    for (const auto& [name, node] : *widgetTbl) {
      auto* entryTbl = node.as_table();
      if (entryTbl == nullptr) {
        continue;
      }

      WidgetConfig wc;
      if (auto v = (*entryTbl)["type"].value<std::string>()) {
        wc.type = *v;
      } else {
        wc.type = std::string(name.str());
      }

      for (const auto& [key, val] : *entryTbl) {
        if (key == "type") {
          continue;
        }
        if (auto* s = val.as_string()) {
          wc.settings[std::string(key.str())] = s->get();
        } else if (auto* i = val.as_integer()) {
          wc.settings[std::string(key.str())] = i->get();
        } else if (auto* f = val.as_floating_point()) {
          wc.settings[std::string(key.str())] = f->get();
        } else if (auto* b = val.as_boolean()) {
          wc.settings[std::string(key.str())] = b->get();
        }
      }

      m_config.widgets[std::string(name.str())] = std::move(wc);
    }
  }

  // Parse [shell]
  if (auto* shellTbl = tbl["shell"].as_table()) {
    auto& shell = m_config.shell;
    if (auto v = (*shellTbl)["ui_scale"].value<double>()) {
      shell.uiScale = std::clamp(static_cast<float>(*v), 0.5f, 4.0f);
    }
    if (auto v = (*shellTbl)["lang"].value<std::string>()) {
      shell.lang = *v;
    }
    if (auto notificationsDbus = (*shellTbl)["notifications_dbus"].value<bool>()) {
      shell.notificationsDbus = *notificationsDbus;
    }
    if (const auto* animationTbl = (*shellTbl)["animation"].as_table()) {
      if (auto enabled = (*animationTbl)["enabled"].value<bool>()) {
        shell.animation.enabled = *enabled;
      }
      if (auto v = (*animationTbl)["speed"].value<double>()) {
        shell.animation.speed = std::clamp(static_cast<float>(*v), 0.05f, 4.0f);
      }
    }
    if (auto v = (*shellTbl)["avatar_path"].value<std::string>()) {
      shell.avatarPath = *v;
    }
    if (auto v = (*shellTbl)["clipboard_auto_paste"].value<std::string>()) {
      if (*v == "off") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::Off;
      } else if (*v == "auto") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::Auto;
      } else if (*v == "ctrl_v") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::CtrlV;
      } else if (*v == "ctrl_shift_v") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::CtrlShiftV;
      } else if (*v == "shift_insert") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::ShiftInsert;
      }
    }
  }

  // Parse [theme]
  if (auto* themeTbl = tbl["theme"].as_table()) {
    auto& theme = m_config.theme;
    if (auto v = (*themeTbl)["source"].value<std::string>()) {
      if (*v == "builtin")
        theme.source = ThemeSource::Builtin;
      else if (*v == "wallpaper")
        theme.source = ThemeSource::Wallpaper;
    }
    if (auto builtinPalette = (*themeTbl)["builtin_palette"].value<std::string>()) {
      theme.builtinPalette = *builtinPalette;
    } else if (auto builtin = (*themeTbl)["builtin"].value<std::string>()) {
      theme.builtinPalette = *builtin;
    }
    if (auto v = (*themeTbl)["wallpaper_scheme"].value<std::string>())
      theme.wallpaperScheme = *v;
    if (auto v = (*themeTbl)["mode"].value<std::string>()) {
      if (*v == "dark")
        theme.mode = ThemeMode::Dark;
      else if (*v == "light")
        theme.mode = ThemeMode::Light;
      else if (*v == "auto")
        theme.mode = ThemeMode::Auto;
    }
    if (const auto* templatesTbl = (*themeTbl)["templates"].as_table()) {
      auto& templates = theme.templates;
      if (auto v = (*templatesTbl)["enable_builtins"].value<bool>())
        templates.enableBuiltins = *v;
      if (auto v = (*templatesTbl)["enable_user_templates"].value<bool>())
        templates.enableUserTemplates = *v;
      if (auto v = (*templatesTbl)["user_config"].value<std::string>())
        templates.userConfig = *v;
      if (const auto* builtinIds = (*templatesTbl)["builtin_ids"].as_array()) {
        templates.builtinIds.clear();
        templates.builtinIds.reserve(builtinIds->size());
        for (const auto& item : *builtinIds) {
          if (const auto* id = item.as_string())
            templates.builtinIds.push_back(id->get());
        }
      }
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
    auto parseTransition = [](const std::string& s) -> std::optional<WallpaperTransition> {
      if (s == "fade")
        return WallpaperTransition::Fade;
      if (s == "wipe")
        return WallpaperTransition::Wipe;
      if (s == "disc")
        return WallpaperTransition::Disc;
      if (s == "stripes")
        return WallpaperTransition::Stripes;
      if (s == "zoom")
        return WallpaperTransition::Zoom;
      if (s == "honeycomb")
        return WallpaperTransition::Honeycomb;
      return std::nullopt;
    };
    if (auto* arr = (*wpTbl)["transition"].as_array()) {
      wp.transitions.clear();
      for (const auto& item : *arr) {
        if (auto s = item.value<std::string>()) {
          if (auto t = parseTransition(*s))
            wp.transitions.push_back(*t);
        }
      }
      if (wp.transitions.empty())
        wp.transitions.push_back(WallpaperTransition::Fade);
    }
    if (auto v = (*wpTbl)["transition_duration"].value<double>())
      wp.transitionDurationMs = std::clamp(static_cast<float>(*v), 100.0f, 30000.0f);
    if (auto v = (*wpTbl)["edge_smoothness"].value<double>())
      wp.edgeSmoothness = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*wpTbl)["directory"].value<std::string>())
      wp.directory = *v;
    if (auto v = (*wpTbl)["directory_light"].value<std::string>())
      wp.directoryLight = *v;
    if (auto v = (*wpTbl)["directory_dark"].value<std::string>())
      wp.directoryDark = *v;

    if (auto* monTblMap = (*wpTbl)["monitor"].as_table()) {
      for (const auto& [monName, monNode] : *monTblMap) {
        auto* monTbl = monNode.as_table();
        if (monTbl == nullptr) {
          continue;
        }
        WallpaperMonitorOverride ovr;
        if (auto v = (*monTbl)["match"].value<std::string>())
          ovr.match = *v;
        else
          ovr.match = std::string(monName.str());
        if (auto v = (*monTbl)["enabled"].value<bool>())
          ovr.enabled = *v;
        if (auto v = (*monTbl)["directory"].value<std::string>())
          ovr.directory = *v;
        if (auto v = (*monTbl)["directory_light"].value<std::string>())
          ovr.directoryLight = *v;
        if (auto v = (*monTbl)["directory_dark"].value<std::string>())
          ovr.directoryDark = *v;
        wp.monitorOverrides.push_back(std::move(ovr));
      }
    }
  }

  // Parse [overview]
  if (auto* ovTbl = tbl["overview"].as_table()) {
    auto& ov = m_config.overview;
    if (auto v = (*ovTbl)["enabled"].value<bool>())
      ov.enabled = *v;
    if (auto v = (*ovTbl)["blur_intensity"].value<double>())
      ov.blurIntensity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*ovTbl)["tint_intensity"].value<double>())
      ov.tintIntensity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
  }

  // Parse [osd]
  if (auto* osdTbl = tbl["osd"].as_table()) {
    auto& osd = m_config.osd;
    if (auto v = (*osdTbl)["position"].value<std::string>())
      osd.position = *v;
  }

  // Parse [dock]
  if (auto* dockTbl = tbl["dock"].as_table()) {
    auto& dock = m_config.dock;
    if (auto v = (*dockTbl)["enabled"].value<bool>())
      dock.enabled = *v;
    if (auto v = (*dockTbl)["position"].value<std::string>())
      dock.position = *v;
    if (auto v = (*dockTbl)["icon_size"].value<int64_t>())
      dock.iconSize = std::clamp(static_cast<std::int32_t>(*v), 16, 256);
    if (auto v = (*dockTbl)["padding"].value<int64_t>())
      dock.padding = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["item_spacing"].value<int64_t>())
      dock.itemSpacing = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["background_opacity"].value<double>())
      dock.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*dockTbl)["radius"].value<int64_t>())
      dock.radius = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
    if (auto v = (*dockTbl)["margin_h"].value<int64_t>())
      dock.marginH = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
    if (auto v = (*dockTbl)["margin_v"].value<int64_t>())
      dock.marginV = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["shadow_blur"].value<int64_t>())
      dock.shadowBlur = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["shadow_offset_x"].value<int64_t>())
      dock.shadowOffsetX = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
    if (auto v = (*dockTbl)["shadow_offset_y"].value<int64_t>())
      dock.shadowOffsetY = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
    if (auto v = (*dockTbl)["show_running"].value<bool>())
      dock.showRunning = *v;
    if (auto v = (*dockTbl)["auto_hide"].value<bool>())
      dock.autoHide = *v;
    if (auto v = (*dockTbl)["indicator_style"].value<std::string>())
      dock.indicatorStyle = *v;
    if (auto v = (*dockTbl)["show_instance_count"].value<bool>())
      dock.showInstanceCount = *v;
    if (auto* arr = (*dockTbl)["pinned"].as_array())
      dock.pinned = readStringArray(*arr);
  }

  // Parse [weather]
  if (auto* weatherTbl = tbl["weather"].as_table()) {
    auto& weather = m_config.weather;
    if (auto v = (*weatherTbl)["enabled"].value<bool>())
      weather.enabled = *v;
    if (auto v = (*weatherTbl)["auto_locate"].value<bool>())
      weather.autoLocate = *v;
    if (auto v = (*weatherTbl)["address"].value<std::string>())
      weather.address = *v;
    if (auto v = (*weatherTbl)["refresh_minutes"].value<int64_t>())
      weather.refreshMinutes = static_cast<std::int32_t>(*v);
    if (auto v = (*weatherTbl)["unit"].value<std::string>())
      weather.unit = *v;
  }

  // Parse [audio]
  if (auto* audioTbl = tbl["audio"].as_table()) {
    auto& audio = m_config.audio;
    if (auto v = (*audioTbl)["enable_overdrive"].value<bool>()) {
      audio.enableOverdrive = *v;
    }
  }

  // Parse [nightlight]
  if (auto* nightlightTbl = tbl["nightlight"].as_table()) {
    auto& nightlight = m_config.nightlight;
    if (auto v = (*nightlightTbl)["enabled"].value<bool>()) {
      nightlight.enabled = *v;
    }
    if (auto v = (*nightlightTbl)["force"].value<bool>()) {
      nightlight.force = *v;
    }
    if (auto v = (*nightlightTbl)["use_weather_location"].value<bool>()) {
      nightlight.useWeatherLocation = *v;
    }
    if (auto v = (*nightlightTbl)["start_time"].value<std::string>()) {
      nightlight.startTime = *v;
    }
    if (auto v = (*nightlightTbl)["stop_time"].value<std::string>()) {
      nightlight.stopTime = *v;
    }
    if (auto v = (*nightlightTbl)["latitude"].value<double>()) {
      nightlight.latitude = *v;
    }
    if (auto v = (*nightlightTbl)["longitude"].value<double>()) {
      nightlight.longitude = *v;
    }
    if (auto v = (*nightlightTbl)["temperature_day"].value<int64_t>()) {
      nightlight.dayTemperature = std::clamp(static_cast<std::int32_t>(*v), 1000, 25000);
    }
    if (auto v = (*nightlightTbl)["temperature_night"].value<int64_t>()) {
      nightlight.nightTemperature = std::clamp(static_cast<std::int32_t>(*v), 1000, 25000);
    }
  }

  // Parse [idle.behavior.*]
  if (auto* idleTbl = tbl["idle"].as_table()) {
    if (auto* behaviorTbl = (*idleTbl)["behavior"].as_table()) {
      for (const auto& [name, node] : *behaviorTbl) {
        auto* entryTbl = node.as_table();
        if (entryTbl == nullptr) {
          continue;
        }

        IdleBehaviorConfig behavior;
        behavior.name = std::string(name.str());

        if (auto v = (*entryTbl)["enabled"].value<bool>()) {
          behavior.enabled = *v;
        }
        if (auto v = (*entryTbl)["timeout"].value<int64_t>()) {
          behavior.timeoutSeconds = static_cast<std::int32_t>(*v);
        }
        if (auto v = (*entryTbl)["command"].value<std::string>()) {
          behavior.command = *v;
        }

        m_config.idle.behaviors.push_back(std::move(behavior));
      }
    }
  }

  if (m_config.bars.empty()) {
    kLog.info("no [bar.*] defined, using defaults");
    m_config.bars.push_back(BarConfig{});
  }

  kLog.info("{} bar(s) defined", m_config.bars.size());
  kLog.info("idle behaviors={}", m_config.idle.behaviors.size());
}

// ── WidgetConfig accessors ───────────────────────────────────────────────────

std::string WidgetConfig::getString(const std::string& key, const std::string& fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::string>(&it->second)) {
    return *v;
  }
  return fallback;
}

std::int64_t WidgetConfig::getInt(const std::string& key, std::int64_t fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::int64_t>(&it->second)) {
    return *v;
  }
  return fallback;
}

double WidgetConfig::getDouble(const std::string& key, double fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<double>(&it->second)) {
    return *v;
  }
  // Allow int → double promotion
  if (const auto* v = std::get_if<std::int64_t>(&it->second)) {
    return static_cast<double>(*v);
  }
  return fallback;
}

bool WidgetConfig::getBool(const std::string& key, bool fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<bool>(&it->second)) {
    return *v;
  }
  return fallback;
}
