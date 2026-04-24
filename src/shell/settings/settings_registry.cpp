#include "shell/settings/settings_registry.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <string>
#include <utility>

namespace settings {
  namespace {

    std::string themeModeToString(ThemeMode mode) {
      switch (mode) {
      case ThemeMode::Dark:
        return "dark";
      case ThemeMode::Light:
        return "light";
      case ThemeMode::Auto:
        return "auto";
      }
      return "dark";
    }

    std::string themeSourceToString(ThemeSource source) {
      switch (source) {
      case ThemeSource::Builtin:
        return "builtin";
      case ThemeSource::Wallpaper:
        return "wallpaper";
      case ThemeSource::Community:
        return "community";
      }
      return "builtin";
    }

    std::string pathText(const std::vector<std::string>& path) {
      std::string out;
      for (const auto& part : path) {
        if (!out.empty()) {
          out.push_back('.');
        }
        out += part;
      }
      return out;
    }

    std::string lower(std::string_view value) {
      std::string out(value);
      std::transform(out.begin(), out.end(), out.begin(),
                     [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
      return out;
    }

    SettingEntry makeEntry(std::string section, std::string title, std::string subtitle, std::vector<std::string> path,
                           SettingControl control, std::string tags = {}) {
      std::string searchText = section + " " + title + " " + subtitle + " " + pathText(path) + " " + tags;
      return SettingEntry{
          .section = std::move(section),
          .title = std::move(title),
          .subtitle = std::move(subtitle),
          .path = std::move(path),
          .control = std::move(control),
          .searchText = lower(searchText),
      };
    }

  } // namespace

  const BarConfig* findBar(const Config& cfg, std::string_view name) {
    for (const auto& bar : cfg.bars) {
      if (bar.name == name) {
        return &bar;
      }
    }
    return nullptr;
  }

  std::vector<std::string> barNames(const Config& cfg) {
    std::vector<std::string> names;
    names.reserve(cfg.bars.size());
    for (const auto& bar : cfg.bars) {
      names.push_back(bar.name);
    }
    return names;
  }

  bool matchesSettingQuery(const SettingEntry& entry, std::string_view query) {
    const std::string q = lower(query);
    if (q.empty()) {
      return true;
    }
    return entry.searchText.find(q) != std::string::npos;
  }

  std::vector<SettingEntry> buildSettingsRegistry(const Config& cfg, const BarConfig* selectedBar) {
    std::vector<SettingEntry> entries;

    entries.push_back(makeEntry("Appearance", "Theme mode", "Final light/dark mode preference.", {"theme", "mode"},
                                SelectSetting{{"dark", "light", "auto"}, themeModeToString(cfg.theme.mode)},
                                "dark light auto colors"));
    entries.push_back(makeEntry(
        "Appearance", "Theme source", "Palette source used by the shell.", {"theme", "source"},
        SelectSetting{{"builtin", "wallpaper", "community"}, themeSourceToString(cfg.theme.source)}, "palette colors"));
    entries.push_back(makeEntry("Appearance", "UI scale", "Global shell content scale.", {"shell", "ui_scale"},
                                SliderSetting{cfg.shell.uiScale, 0.5f, 2.5f, 0.05f, false}, "size"));
    entries.push_back(makeEntry("Appearance", "Animations", "Enable shell transitions and motion.",
                                {"shell", "animation", "enabled"}, ToggleSetting{cfg.shell.animation.enabled},
                                "motion"));
    entries.push_back(makeEntry("Appearance", "Animation speed", "Multiplier for transition speed.",
                                {"shell", "animation", "speed"},
                                SliderSetting{cfg.shell.animation.speed, 0.1f, 4.0f, 0.05f, false}, "motion"));

    entries.push_back(makeEntry("Dock", "Enabled", "Show the application dock.", {"dock", "enabled"},
                                ToggleSetting{cfg.dock.enabled}, "launcher apps"));
    entries.push_back(makeEntry("Dock", "Position", "Screen edge used by the dock.", {"dock", "position"},
                                SelectSetting{{"top", "bottom", "left", "right"}, cfg.dock.position}, "edge"));
    entries.push_back(makeEntry("Dock", "Icon size", "Dock icon size in pixels.", {"dock", "icon_size"},
                                SliderSetting{static_cast<float>(cfg.dock.iconSize), 16.0f, 128.0f, 1.0f, true},
                                "apps"));
    entries.push_back(makeEntry("Dock", "Auto hide", "Hide the dock until pointer approach.", {"dock", "auto_hide"},
                                ToggleSetting{cfg.dock.autoHide}, "autohide"));
    entries.push_back(makeEntry("Dock", "Show running apps", "Include unpinned running applications.",
                                {"dock", "show_running"}, ToggleSetting{cfg.dock.showRunning}, "windows"));

    entries.push_back(makeEntry("Services", "Weather", "Enable forecast data and weather surfaces.",
                                {"weather", "enabled"}, ToggleSetting{cfg.weather.enabled}, "forecast"));
    entries.push_back(makeEntry("Services", "Weather location", "Resolve location from IP instead of address.",
                                {"weather", "auto_locate"}, ToggleSetting{cfg.weather.autoLocate}, "forecast gps"));
    entries.push_back(makeEntry("Services", "Weather unit", "Temperature unit for forecasts.", {"weather", "unit"},
                                SelectSetting{{"celsius", "fahrenheit"}, cfg.weather.unit}, "temperature"));
    entries.push_back(makeEntry("Services", "Night light", "Enable scheduled display warmth.",
                                {"nightlight", "enabled"}, ToggleSetting{cfg.nightlight.enabled}, "wlsunset"));
    entries.push_back(makeEntry(
        "Services", "Night temperature", "Warm color temperature in Kelvin.", {"nightlight", "temperature_night"},
        SliderSetting{static_cast<float>(cfg.nightlight.nightTemperature), 1000.0f, 10000.0f, 100.0f, true},
        "wlsunset kelvin"));

    entries.push_back(makeEntry("Notifications", "Notification daemon", "Claim org.freedesktop.Notifications.",
                                {"notification", "enable_daemon"}, ToggleSetting{cfg.notification.enableDaemon},
                                "dbus"));
    entries.push_back(makeEntry("Notifications", "Toast blur", "Request compositor blur behind toasts.",
                                {"notification", "background_blur"}, ToggleSetting{cfg.notification.backgroundBlur},
                                "popup"));
    entries.push_back(makeEntry("Notifications", "Toast opacity", "Toast card background alpha.",
                                {"notification", "background_opacity"},
                                SliderSetting{cfg.notification.backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "popup"));

    if (selectedBar != nullptr) {
      const std::string section = "Bar";
      const std::vector<std::string> root = {"bar", selectedBar->name};
      auto path = [&](std::string key) {
        std::vector<std::string> p = root;
        p.push_back(std::move(key));
        return p;
      };
      entries.push_back(makeEntry(section, "Position", "Screen edge used by this bar.", path("position"),
                                  SelectSetting{{"top", "bottom", "left", "right"}, selectedBar->position}, "edge"));
      entries.push_back(makeEntry(section, "Auto hide", "Slide the bar out when inactive.", path("auto_hide"),
                                  ToggleSetting{selectedBar->autoHide}, "autohide"));
      entries.push_back(makeEntry(section, "Reserve space", "Keep compositor exclusive zone for the bar.",
                                  path("reserve_space"), ToggleSetting{selectedBar->reserveSpace}, "exclusive zone"));
      entries.push_back(makeEntry(section, "Thickness", "Bar cross-axis size in pixels.", path("thickness"),
                                  SliderSetting{static_cast<float>(selectedBar->thickness), 10.0f, 120.0f, 1.0f, true},
                                  "height width"));
      entries.push_back(makeEntry(section, "Background opacity", "Bar background alpha.", path("background_opacity"),
                                  SliderSetting{selectedBar->backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "alpha"));
      entries.push_back(makeEntry(section, "Widget capsules", "Default capsule background for widgets.",
                                  path("capsule"), ToggleSetting{selectedBar->widgetCapsuleDefault}, "pill"));
      entries.push_back(
          makeEntry(section, "Widget spacing", "Gap between widgets in each lane.", path("widget_spacing"),
                    SliderSetting{static_cast<float>(selectedBar->widgetSpacing), 0.0f, 32.0f, 1.0f, true}, "gap"));
    }

    return entries;
  }

} // namespace settings
