#include "shell/settings/settings_registry.h"

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <utility>

namespace settings {
  namespace {

    template <typename T> struct EnumOption {
      T value;
      std::string_view key;
    };

    constexpr EnumOption<ThemeMode> kThemeModes[] = {
        {ThemeMode::Dark, "dark"},
        {ThemeMode::Light, "light"},
        {ThemeMode::Auto, "auto"},
    };

    constexpr EnumOption<ThemeSource> kThemeSources[] = {
        {ThemeSource::Builtin, "builtin"},
        {ThemeSource::Wallpaper, "wallpaper"},
        {ThemeSource::Community, "community"},
    };

    constexpr EnumOption<ClipboardAutoPasteMode> kClipboardAutoPasteModes[] = {
        {ClipboardAutoPasteMode::Off, "off"},
        {ClipboardAutoPasteMode::Auto, "auto"},
        {ClipboardAutoPasteMode::CtrlV, "ctrl_v"},
        {ClipboardAutoPasteMode::CtrlShiftV, "ctrl_shift_v"},
        {ClipboardAutoPasteMode::ShiftInsert, "shift_insert"},
    };

    constexpr EnumOption<PasswordMaskStyle> kPasswordMaskStyles[] = {
        {PasswordMaskStyle::CircleFilled, "default"},
        {PasswordMaskStyle::RandomIcons, "random"},
    };

    template <typename T, std::size_t N> std::vector<std::string> optionKeys(const EnumOption<T> (&options)[N]) {
      std::vector<std::string> keys;
      keys.reserve(N);
      for (const auto& option : options) {
        keys.emplace_back(option.key);
      }
      return keys;
    }

    template <typename T, std::size_t N> std::string selectedKey(T value, const EnumOption<T> (&options)[N]) {
      for (const auto& option : options) {
        if (option.value == value) {
          return std::string(option.key);
        }
      }
      if constexpr (N > 0) {
        return std::string(options[0].key);
      }
      return {};
    }

    template <typename T, std::size_t N> SelectSetting enumSelect(const EnumOption<T> (&options)[N], T selected) {
      return SelectSetting{optionKeys(options), selectedKey(selected, options)};
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

    SettingEntry makeEntry(std::string section, std::string group, std::string title, std::string subtitle,
                           std::vector<std::string> path, SettingControl control, std::string tags = {},
                           bool advanced = false) {
      std::string searchText = section + " " + group + " " + title + " " + subtitle + " " + pathText(path) + " " + tags;
      if (advanced) {
        searchText += " advanced";
      }
      return SettingEntry{
          .section = std::move(section),
          .group = std::move(group),
          .title = std::move(title),
          .subtitle = std::move(subtitle),
          .path = std::move(path),
          .control = std::move(control),
          .advanced = advanced,
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

    entries.push_back(makeEntry("Appearance", "Theme", "Theme mode", "Final light/dark mode preference.",
                                {"theme", "mode"}, enumSelect(kThemeModes, cfg.theme.mode), "dark light auto colors"));
    entries.push_back(makeEntry("Appearance", "Theme", "Theme source", "Palette source used by the shell.",
                                {"theme", "source"}, enumSelect(kThemeSources, cfg.theme.source), "palette colors"));
    entries.push_back(makeEntry("Appearance", "Interface", "UI scale", "Global shell content scale.",
                                {"shell", "ui_scale"}, SliderSetting{cfg.shell.uiScale, 0.5f, 2.5f, 0.05f, false},
                                "size"));
    entries.push_back(makeEntry("Appearance", "Motion", "Animations", "Enable shell transitions and motion.",
                                {"shell", "animation", "enabled"}, ToggleSetting{cfg.shell.animation.enabled},
                                "motion"));
    entries.push_back(makeEntry("Appearance", "Motion", "Animation speed", "Multiplier for transition speed.",
                                {"shell", "animation", "speed"},
                                SliderSetting{cfg.shell.animation.speed, 0.1f, 4.0f, 0.05f, false}, "motion"));

    entries.push_back(makeEntry("Shell", "Security", "Polkit agent", "Run Noctalia's authentication agent.",
                                {"shell", "polkit_agent"}, ToggleSetting{cfg.shell.polkitAgent}, "auth password"));
    entries.push_back(makeEntry("Shell", "Security", "Password style", "Mask style used by password inputs.",
                                {"shell", "password_style"},
                                enumSelect(kPasswordMaskStyles, cfg.shell.passwordMaskStyle), "polkit lock mask"));
    entries.push_back(makeEntry("Shell", "Location", "Show location", "Allow shell surfaces to show location names.",
                                {"shell", "show_location"}, ToggleSetting{cfg.shell.showLocation}, "weather"));
    entries.push_back(makeEntry("Shell", "Clipboard", "Clipboard auto paste",
                                "Paste clipboard picker selections automatically.", {"shell", "clipboard_auto_paste"},
                                enumSelect(kClipboardAutoPasteModes, cfg.shell.clipboardAutoPaste), "clipboard paste"));
    entries.push_back(makeEntry(
        "Shell", "OSD", "OSD position", "Screen location for volume and brightness HUDs.", {"osd", "position"},
        SelectSetting{{"top_right", "top_left", "top_center", "bottom_right", "bottom_left", "bottom_center"},
                      cfg.osd.position},
        "hud overlay volume brightness"));

    entries.push_back(makeEntry("Dock", "General", "Enabled", "Show the application dock.", {"dock", "enabled"},
                                ToggleSetting{cfg.dock.enabled}, "launcher apps"));
    entries.push_back(makeEntry("Dock", "General", "Active monitor only", "Render the dock only on the active output.",
                                {"dock", "active_monitor_only"}, ToggleSetting{cfg.dock.activeMonitorOnly}, "monitor"));
    entries.push_back(makeEntry("Dock", "Layout", "Position", "Screen edge used by the dock.", {"dock", "position"},
                                SelectSetting{{"top", "bottom", "left", "right"}, cfg.dock.position}, "edge"));
    entries.push_back(makeEntry("Dock", "Layout", "Icon size", "Dock icon size in pixels.", {"dock", "icon_size"},
                                SliderSetting{static_cast<float>(cfg.dock.iconSize), 16.0f, 128.0f, 1.0f, true},
                                "apps"));
    entries.push_back(makeEntry("Dock", "Layout", "Padding", "Inner padding around dock items.", {"dock", "padding"},
                                SliderSetting{static_cast<float>(cfg.dock.padding), 0.0f, 100.0f, 1.0f, true},
                                "inset"));
    entries.push_back(makeEntry("Dock", "Layout", "Item spacing", "Gap between dock items.", {"dock", "item_spacing"},
                                SliderSetting{static_cast<float>(cfg.dock.itemSpacing), 0.0f, 100.0f, 1.0f, true},
                                "gap"));
    entries.push_back(
        makeEntry("Dock", "Layout", "Horizontal margin", "Horizontal margin from screen edges.", {"dock", "margin_h"},
                  SliderSetting{static_cast<float>(cfg.dock.marginH), 0.0f, 500.0f, 1.0f, true}, "gap inset"));
    entries.push_back(
        makeEntry("Dock", "Layout", "Vertical margin", "Gap between dock and screen edge.", {"dock", "margin_v"},
                  SliderSetting{static_cast<float>(cfg.dock.marginV), 0.0f, 100.0f, 1.0f, true}, "gap inset"));
    entries.push_back(makeEntry("Dock", "Shape", "Corner radius", "Dock background corner radius.", {"dock", "radius"},
                                SliderSetting{static_cast<float>(cfg.dock.radius), 0.0f, 80.0f, 1.0f, true},
                                "rounded"));
    entries.push_back(makeEntry("Dock", "Shape", "Background opacity", "Dock background alpha.",
                                {"dock", "background_opacity"},
                                SliderSetting{cfg.dock.backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "alpha"));
    entries.push_back(makeEntry("Dock", "Effects", "Background blur", "Request compositor blur behind the dock.",
                                {"dock", "background_blur"}, ToggleSetting{cfg.dock.backgroundBlur}, "blur"));
    entries.push_back(makeEntry("Dock", "Effects", "Shadow blur", "Dock shadow blur radius.", {"dock", "shadow_blur"},
                                SliderSetting{static_cast<float>(cfg.dock.shadowBlur), 0.0f, 100.0f, 1.0f, true},
                                "shadow", true));
    entries.push_back(makeEntry(
        "Dock", "Effects", "Shadow X offset", "Horizontal shadow offset.", {"dock", "shadow_offset_x"},
        SliderSetting{static_cast<float>(cfg.dock.shadowOffsetX), -40.0f, 40.0f, 1.0f, true}, "shadow", true));
    entries.push_back(makeEntry(
        "Dock", "Effects", "Shadow Y offset", "Vertical shadow offset.", {"dock", "shadow_offset_y"},
        SliderSetting{static_cast<float>(cfg.dock.shadowOffsetY), -40.0f, 40.0f, 1.0f, true}, "shadow", true));
    entries.push_back(makeEntry("Dock", "Behavior", "Auto hide", "Hide the dock until pointer approach.",
                                {"dock", "auto_hide"}, ToggleSetting{cfg.dock.autoHide}, "autohide"));
    entries.push_back(makeEntry("Dock", "Behavior", "Reserve space", "Keep compositor exclusive zone for the dock.",
                                {"dock", "reserve_space"}, ToggleSetting{cfg.dock.reserveSpace}, "exclusive zone"));
    entries.push_back(makeEntry("Dock", "Behavior", "Show running apps", "Include unpinned running applications.",
                                {"dock", "show_running"}, ToggleSetting{cfg.dock.showRunning}, "windows"));
    entries.push_back(makeEntry("Dock", "Behavior", "Show instance count",
                                "Show a badge when an app has multiple windows.", {"dock", "show_instance_count"},
                                ToggleSetting{cfg.dock.showInstanceCount}, "badge windows"));
    entries.push_back(makeEntry("Dock", "Focus styling", "Active icon scale", "Scale for the focused app icon.",
                                {"dock", "active_scale"},
                                SliderSetting{cfg.dock.activeScale, 0.1f, 1.75f, 0.05f, false}, "focused", true));
    entries.push_back(makeEntry("Dock", "Focus styling", "Inactive icon scale", "Scale for non-focused app icons.",
                                {"dock", "inactive_scale"},
                                SliderSetting{cfg.dock.inactiveScale, 0.1f, 1.0f, 0.05f, false}, "unfocused", true));
    entries.push_back(makeEntry(
        "Dock", "Focus styling", "Active icon opacity", "Opacity for the focused app icon.", {"dock", "active_opacity"},
        SliderSetting{cfg.dock.activeOpacity, 0.0f, 1.0f, 0.01f, false}, "focused alpha", true));
    entries.push_back(makeEntry("Dock", "Focus styling", "Inactive icon opacity", "Opacity for non-focused app icons.",
                                {"dock", "inactive_opacity"},
                                SliderSetting{cfg.dock.inactiveOpacity, 0.0f, 1.0f, 0.01f, false}, "unfocused alpha",
                                true));

    entries.push_back(makeEntry("Overview", "General", "Enabled", "Show the overview backdrop surface.",
                                {"overview", "enabled"}, ToggleSetting{cfg.overview.enabled}, "wallpaper backdrop"));
    entries.push_back(makeEntry("Overview", "General", "Unload when hidden",
                                "Release overview resources when not in use.", {"overview", "unload_when_not_in_use"},
                                ToggleSetting{cfg.overview.unloadWhenNotInUse}, "memory"));
    entries.push_back(makeEntry("Overview", "Backdrop", "Blur intensity", "Overview wallpaper blur amount.",
                                {"overview", "blur_intensity"},
                                SliderSetting{cfg.overview.blurIntensity, 0.0f, 1.0f, 0.01f, false}, "wallpaper"));
    entries.push_back(makeEntry("Overview", "Backdrop", "Tint intensity", "Overview wallpaper tint amount.",
                                {"overview", "tint_intensity"},
                                SliderSetting{cfg.overview.tintIntensity, 0.0f, 1.0f, 0.01f, false}, "wallpaper"));

    entries.push_back(makeEntry("Desktop", "Widgets", "Desktop widgets", "Render configured desktop widgets.",
                                {"desktop_widgets", "enabled"}, ToggleSetting{cfg.desktopWidgets.enabled}, "desktop"));

    entries.push_back(makeEntry("Services", "Weather", "Weather", "Enable forecast data and weather surfaces.",
                                {"weather", "enabled"}, ToggleSetting{cfg.weather.enabled}, "forecast"));
    entries.push_back(makeEntry("Services", "Weather", "Weather location",
                                "Resolve location from IP instead of address.", {"weather", "auto_locate"},
                                ToggleSetting{cfg.weather.autoLocate}, "forecast gps"));
    entries.push_back(makeEntry("Services", "Weather", "Weather unit", "Temperature unit for forecasts.",
                                {"weather", "unit"}, SelectSetting{{"celsius", "fahrenheit"}, cfg.weather.unit},
                                "temperature"));
    entries.push_back(makeEntry("Services", "Weather", "Weather effects", "Enable weather visual effects.",
                                {"weather", "effects"}, ToggleSetting{cfg.weather.effects}, "forecast visuals"));
    entries.push_back(makeEntry(
        "Services", "Weather", "Refresh interval", "Minutes between weather refreshes.", {"weather", "refresh_minutes"},
        SliderSetting{static_cast<float>(cfg.weather.refreshMinutes), 5.0f, 240.0f, 5.0f, true}, "forecast"));
    entries.push_back(makeEntry("Services", "Audio", "Audio overdrive", "Allow volume above 100%.",
                                {"audio", "enable_overdrive"}, ToggleSetting{cfg.audio.enableOverdrive}, "volume"));
    entries.push_back(makeEntry("Services", "Audio", "Shell sounds", "Enable shell feedback sounds.",
                                {"audio", "enable_sounds"}, ToggleSetting{cfg.audio.enableSounds}, "sound"));
    entries.push_back(makeEntry("Services", "Audio", "Sound volume", "Volume for shell feedback sounds.",
                                {"audio", "sound_volume"},
                                SliderSetting{cfg.audio.soundVolume, 0.0f, 1.0f, 0.01f, false}, "sound"));
    entries.push_back(makeEntry("Services", "Brightness", "DDC/CI brightness", "Enable ddcutil for external monitors.",
                                {"brightness", "enable_ddcutil"}, ToggleSetting{cfg.brightness.enableDdcutil},
                                "monitor ddcutil"));
    entries.push_back(makeEntry("Services", "Night light", "Night light", "Enable scheduled display warmth.",
                                {"nightlight", "enabled"}, ToggleSetting{cfg.nightlight.enabled}, "wlsunset"));
    entries.push_back(makeEntry("Services", "Night light", "Force night light", "Keep night light active now.",
                                {"nightlight", "force"}, ToggleSetting{cfg.nightlight.force}, "wlsunset"));
    entries.push_back(makeEntry("Services", "Night light", "Use weather location",
                                "Use weather coordinates for the schedule.", {"nightlight", "use_weather_location"},
                                ToggleSetting{cfg.nightlight.useWeatherLocation}, "location"));
    entries.push_back(
        makeEntry("Services", "Night light", "Day temperature", "Day color temperature in Kelvin.",
                  {"nightlight", "temperature_day"},
                  SliderSetting{static_cast<float>(cfg.nightlight.dayTemperature), 1000.0f, 10000.0f, 100.0f, true},
                  "wlsunset kelvin"));
    entries.push_back(
        makeEntry("Services", "Night light", "Night temperature", "Warm color temperature in Kelvin.",
                  {"nightlight", "temperature_night"},
                  SliderSetting{static_cast<float>(cfg.nightlight.nightTemperature), 1000.0f, 10000.0f, 100.0f, true},
                  "wlsunset kelvin"));

    entries.push_back(makeEntry("Notifications", "General", "Notification daemon",
                                "Claim org.freedesktop.Notifications.", {"notification", "enable_daemon"},
                                ToggleSetting{cfg.notification.enableDaemon}, "dbus"));
    entries.push_back(makeEntry("Notifications", "Toasts", "Toast blur", "Request compositor blur behind toasts.",
                                {"notification", "background_blur"}, ToggleSetting{cfg.notification.backgroundBlur},
                                "popup"));
    entries.push_back(makeEntry("Notifications", "Toasts", "Toast opacity", "Toast card background alpha.",
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
      entries.push_back(makeEntry(section, "General", "Enabled", "Show this bar.", path("enabled"),
                                  ToggleSetting{selectedBar->enabled}, "visible"));
      entries.push_back(makeEntry(section, "General", "Position", "Screen edge used by this bar.", path("position"),
                                  SelectSetting{{"top", "bottom", "left", "right"}, selectedBar->position}, "edge"));
      entries.push_back(makeEntry(section, "General", "Auto hide", "Slide the bar out when inactive.",
                                  path("auto_hide"), ToggleSetting{selectedBar->autoHide}, "autohide"));
      entries.push_back(makeEntry(section, "General", "Reserve space", "Keep compositor exclusive zone for the bar.",
                                  path("reserve_space"), ToggleSetting{selectedBar->reserveSpace}, "exclusive zone"));
      entries.push_back(makeEntry(section, "Layout", "Thickness", "Bar cross-axis size in pixels.", path("thickness"),
                                  SliderSetting{static_cast<float>(selectedBar->thickness), 10.0f, 120.0f, 1.0f, true},
                                  "height width"));
      entries.push_back(makeEntry(section, "Layout", "Content scale", "Scale widgets and labels in this bar.",
                                  path("scale"), SliderSetting{selectedBar->scale, 0.5f, 4.0f, 0.05f, false},
                                  "zoom size"));
      entries.push_back(
          makeEntry(section, "Layout", "Horizontal margin", "Left and right compositor margin.", path("margin_h"),
                    SliderSetting{static_cast<float>(selectedBar->marginH), 0.0f, 500.0f, 1.0f, true}, "gap inset"));
      entries.push_back(
          makeEntry(section, "Layout", "Vertical margin", "Gap between the bar and screen edge.", path("margin_v"),
                    SliderSetting{static_cast<float>(selectedBar->marginV), 0.0f, 100.0f, 1.0f, true}, "gap inset"));
      entries.push_back(
          makeEntry(section, "Layout", "Content padding", "Inset between bar edges and widget lanes.", path("padding"),
                    SliderSetting{static_cast<float>(selectedBar->padding), 0.0f, 80.0f, 1.0f, true}, "inset"));
      entries.push_back(makeEntry(section, "Shape", "Corner radius", "Round all bar corners.", path("radius"),
                                  SliderSetting{static_cast<float>(selectedBar->radius), 0.0f, 80.0f, 1.0f, true},
                                  "rounded"));
      entries.push_back(makeEntry(section, "Shape", "Background opacity", "Bar background alpha.",
                                  path("background_opacity"),
                                  SliderSetting{selectedBar->backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "alpha"));
      entries.push_back(makeEntry(section, "Effects", "Background blur", "Request compositor blur behind this bar.",
                                  path("background_blur"), ToggleSetting{selectedBar->backgroundBlur}, "blur"));
      entries.push_back(makeEntry(section, "Effects", "Shadow blur", "Bar shadow blur radius.", path("shadow_blur"),
                                  SliderSetting{static_cast<float>(selectedBar->shadowBlur), 0.0f, 100.0f, 1.0f, true},
                                  "shadow", true));
      entries.push_back(makeEntry(
          section, "Effects", "Shadow X offset", "Horizontal shadow offset.", path("shadow_offset_x"),
          SliderSetting{static_cast<float>(selectedBar->shadowOffsetX), -40.0f, 40.0f, 1.0f, true}, "shadow", true));
      entries.push_back(makeEntry(
          section, "Effects", "Shadow Y offset", "Vertical shadow offset.", path("shadow_offset_y"),
          SliderSetting{static_cast<float>(selectedBar->shadowOffsetY), -40.0f, 40.0f, 1.0f, true}, "shadow", true));
      entries.push_back(makeEntry(section, "Widgets", "Widget capsules", "Default capsule background for widgets.",
                                  path("capsule"), ToggleSetting{selectedBar->widgetCapsuleDefault}, "pill"));
      entries.push_back(
          makeEntry(section, "Widgets", "Widget spacing", "Gap between widgets in each lane.", path("widget_spacing"),
                    SliderSetting{static_cast<float>(selectedBar->widgetSpacing), 0.0f, 32.0f, 1.0f, true}, "gap"));
      entries.push_back(makeEntry(
          section, "Widgets", "Capsule padding", "Inset inside inherited widget capsules.", path("capsule_padding"),
          SliderSetting{selectedBar->widgetCapsulePadding, 0.0f, 48.0f, 1.0f, false}, "pill inset", true));
      entries.push_back(makeEntry(
          section, "Widgets", "Capsule opacity", "Opacity multiplier for widget capsules.", path("capsule_opacity"),
          SliderSetting{selectedBar->widgetCapsuleOpacity, 0.0f, 1.0f, 0.01f, false}, "pill alpha", true));
    }

    return entries;
  }

} // namespace settings
