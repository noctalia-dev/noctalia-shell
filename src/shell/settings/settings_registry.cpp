#include "shell/settings/settings_registry.h"

#include "i18n/i18n.h"
#include "render/core/color.h"
#include "theme/builtin_palettes.h"
#include "theme/builtin_templates.h"

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <string>
#include <string_view>
#include <utility>

namespace settings {
  namespace {

    template <typename T, std::size_t N> SelectSetting enumSelect(const EnumOption<T> (&options)[N], T selected) {
      std::vector<SelectOption> opts;
      opts.reserve(N);
      std::string selectedValue;
      for (const auto& option : options) {
        std::string key(option.key);
        if (option.value == selected) {
          selectedValue = key;
        }
        opts.push_back(SelectOption{std::move(key), i18n::tr(option.labelKey)});
      }
      if (selectedValue.empty() && N > 0) {
        selectedValue = std::string(options[0].key);
      }
      return SelectSetting{std::move(opts), std::move(selectedValue)};
    }

    SelectSetting plainSelect(std::initializer_list<std::pair<std::string_view, std::string_view>> items,
                              std::string_view selected) {
      std::vector<SelectOption> opts;
      opts.reserve(items.size());
      for (const auto& [value, labelKey] : items) {
        opts.push_back(SelectOption{std::string(value), i18n::tr(labelKey)});
      }
      return SelectSetting{std::move(opts), std::string(selected)};
    }

    SelectSetting builtinPaletteSelect(std::string_view selected) {
      std::vector<SelectOption> opts;
      opts.reserve(noctalia::theme::builtinPalettes().size());
      for (const auto& palette : noctalia::theme::builtinPalettes()) {
        opts.push_back(SelectOption{std::string(palette.name), std::string(palette.name)});
      }
      return SelectSetting{std::move(opts), std::string(selected)};
    }

    SelectSetting wallpaperSchemeSelect(std::string_view selected) {
      return plainSelect({{"m3-content", "theme.scheme.m3-content"},
                          {"m3-tonal-spot", "theme.scheme.m3-tonal-spot"},
                          {"m3-fruit-salad", "theme.scheme.m3-fruit-salad"},
                          {"m3-rainbow", "theme.scheme.m3-rainbow"},
                          {"m3-monochrome", "theme.scheme.m3-monochrome"},
                          {"vibrant", "theme.scheme.vibrant"},
                          {"faithful", "theme.scheme.faithful"},
                          {"dysfunctional", "theme.scheme.dysfunctional"},
                          {"muted", "theme.scheme.muted"}},
                         selected);
    }

    SelectSetting languageSelect(std::string_view selected) {
      std::vector<SelectOption> opts;
      opts.reserve(i18n::kSupportedLanguages.size() + 1);
      opts.push_back(SelectOption{"", i18n::tr("common.auto")});
      for (const auto& language : i18n::kSupportedLanguages) {
        opts.push_back(SelectOption{std::string(language.code), std::string(language.displayName)});
      }
      return SelectSetting{std::move(opts), std::string(selected)};
    }

    std::string colorRoleValue(const ThemeColor& color) {
      if (color.role.has_value()) {
        return std::string(colorRoleToken(*color.role));
      }
      return {};
    }

    std::string optionalColorRoleValue(const std::optional<ThemeColor>& color) {
      if (color.has_value()) {
        return colorRoleValue(*color);
      }
      return {};
    }

    void appendColorRoleOptions(std::vector<SelectOption>& opts) {
      for (const auto& option : kColorRoleTokens) {
        opts.push_back(SelectOption{std::string(option.token), std::string(option.token)});
      }
    }

    SelectSetting colorRoleSelect(const ThemeColor& selected) {
      std::vector<SelectOption> opts;
      opts.reserve(kColorRoleTokens.size());
      appendColorRoleOptions(opts);
      return SelectSetting{std::move(opts), colorRoleValue(selected)};
    }

    SelectSetting optionalColorRoleSelect(const std::optional<ThemeColor>& selected) {
      std::vector<SelectOption> opts;
      opts.reserve(kColorRoleTokens.size() + 1);
      opts.push_back(SelectOption{"", i18n::tr("settings.color-default")});
      appendColorRoleOptions(opts);
      return SelectSetting{std::move(opts), optionalColorRoleValue(selected), true};
    }

    SelectSetting capsuleBorderRoleSelect(const std::optional<ThemeColor>& selected) {
      std::vector<SelectOption> opts;
      opts.reserve(kColorRoleTokens.size() + 1);
      opts.push_back(SelectOption{"", i18n::tr("settings.no-border")});
      appendColorRoleOptions(opts);
      return SelectSetting{std::move(opts), optionalColorRoleValue(selected)};
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

  const BarMonitorOverride* findMonitorOverride(const BarConfig& bar, std::string_view match) {
    for (const auto& ovr : bar.monitorOverrides) {
      if (ovr.match == match) {
        return &ovr;
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

  std::string_view sectionGlyph(std::string_view section) {
    if (section == "appearance")
      return "adjustments-horizontal";
    if (section == "templates")
      return "color-swatch";
    if (section == "shell")
      return "app-window";
    if (section == "dock")
      return "apps";
    if (section == "overview")
      return "layout-grid";
    if (section == "wallpaper")
      return "wallpaper-selector";
    if (section == "desktop")
      return "device-desktop";
    if (section == "services")
      return "stack-2";
    if (section == "notifications")
      return "bell";
    if (section == "bar")
      return "menu";
    return "settings";
  }

  std::vector<SettingEntry> buildSettingsRegistry(const Config& cfg, const BarConfig* selectedBar,
                                                  const BarMonitorOverride* selectedMonitorOverride,
                                                  const RegistryEnvironment& env) {
    using i18n::tr;
    const auto positionSelect = [](std::string_view selected) {
      return plainSelect(
          {{"top", "common.top"}, {"bottom", "common.bottom"}, {"left", "common.left"}, {"right", "common.right"}},
          selected);
    };
    std::vector<SettingEntry> entries;

    // Appearance
    entries.push_back(makeEntry("appearance", "theme", tr("settings.theme-mode"), tr("settings.theme-mode-desc"),
                                {"theme", "mode"}, enumSelect(kThemeModes, cfg.theme.mode), "dark light auto colors"));
    entries.push_back(makeEntry("appearance", "theme", tr("settings.theme-source"), tr("settings.theme-source-desc"),
                                {"theme", "source"}, enumSelect(kThemeSources, cfg.theme.source), "palette colors"));
    if (cfg.theme.source == ThemeSource::Builtin) {
      entries.push_back(makeEntry("appearance", "theme", tr("settings.theme-palette"),
                                  tr("settings.theme-palette-desc"), {"theme", "builtin"},
                                  builtinPaletteSelect(cfg.theme.builtinPalette), "builtin palette colors"));
    } else if (cfg.theme.source == ThemeSource::Wallpaper) {
      entries.push_back(makeEntry("appearance", "theme", tr("settings.wallpaper-generation-scheme"),
                                  tr("settings.wallpaper-generation-scheme-desc"), {"theme", "wallpaper_scheme"},
                                  wallpaperSchemeSelect(cfg.theme.wallpaperScheme),
                                  "wallpaper palette generator scheme material you m3 colors"));
    } else if (cfg.theme.source == ThemeSource::Community) {
      entries.push_back(makeEntry("appearance", "theme", tr("settings.community-palette"),
                                  tr("settings.community-palette-desc"), {"theme", "community_palette"},
                                  TextSetting{cfg.theme.communityPalette, "Noctalia"}, "community palette colors"));
    }
    entries.push_back(makeEntry("appearance", "interface", tr("settings.ui-scale"), tr("settings.ui-scale-desc"),
                                {"shell", "ui_scale"}, SliderSetting{cfg.shell.uiScale, 0.5f, 2.5f, 0.05f, false},
                                "size"));
    entries.push_back(makeEntry("appearance", "interface", tr("settings.font-family"), tr("settings.font-family-desc"),
                                {"shell", "font_family"}, TextSetting{cfg.shell.fontFamily, "sans-serif"}, "typeface"));
    entries.push_back(makeEntry("appearance", "interface", tr("settings.language"), tr("settings.language-desc"),
                                {"shell", "lang"}, languageSelect(cfg.shell.lang), "locale translation", true));
    entries.push_back(makeEntry("appearance", "motion", tr("settings.animations"), tr("settings.animations-desc"),
                                {"shell", "animation", "enabled"}, ToggleSetting{cfg.shell.animation.enabled},
                                "motion"));
    entries.push_back(makeEntry("appearance", "motion", tr("settings.animation-speed"),
                                tr("settings.animation-speed-desc"), {"shell", "animation", "speed"},
                                SliderSetting{cfg.shell.animation.speed, 0.1f, 4.0f, 0.05f, false}, "motion"));
    entries.push_back(makeEntry("appearance", "effects", tr("common.shadow-blur"),
                                tr("settings.global-shadow-blur-desc"), {"shell", "shadow", "blur"},
                                SliderSetting{static_cast<float>(cfg.shell.shadow.blur), 0.0f, 100.0f, 1.0f, true},
                                "shadow depth"));
    entries.push_back(makeEntry("appearance", "effects", tr("common.shadow-x"), tr("settings.global-shadow-x-desc"),
                                {"shell", "shadow", "offset_x"},
                                SliderSetting{static_cast<float>(cfg.shell.shadow.offsetX), -40.0f, 40.0f, 1.0f, true},
                                "shadow offset", true));
    entries.push_back(makeEntry("appearance", "effects", tr("common.shadow-y"), tr("settings.global-shadow-y-desc"),
                                {"shell", "shadow", "offset_y"},
                                SliderSetting{static_cast<float>(cfg.shell.shadow.offsetY), -40.0f, 40.0f, 1.0f, true},
                                "shadow offset", true));
    entries.push_back(makeEntry("appearance", "effects", tr("common.shadow-alpha"),
                                tr("settings.global-shadow-alpha-desc"), {"shell", "shadow", "alpha"},
                                SliderSetting{cfg.shell.shadow.alpha, 0.0f, 1.0f, 0.01f, false}, "shadow opacity",
                                true));

    // Wallpaper
    entries.push_back(makeEntry("wallpaper", "general", tr("common.enabled"), tr("settings.wallpaper-enabled-desc"),
                                {"wallpaper", "enabled"}, ToggleSetting{cfg.wallpaper.enabled}, "background image"));
    entries.push_back(makeEntry("wallpaper", "general", tr("settings.wallpaper-fill-mode"),
                                tr("settings.wallpaper-fill-mode-desc"), {"wallpaper", "fill_mode"},
                                enumSelect(kWallpaperFillModes, cfg.wallpaper.fillMode), "scale aspect"));
    {
      ColorSetting fillColor;
      fillColor.unset = !cfg.wallpaper.fillColor.has_value();
      if (!fillColor.unset) {
        fillColor.hex = formatRgbHex(resolveThemeColor(*cfg.wallpaper.fillColor));
      }
      entries.push_back(makeEntry("wallpaper", "general", tr("settings.wallpaper-fill-color"),
                                  tr("settings.wallpaper-fill-color-desc"), {"wallpaper", "fill_color"},
                                  std::move(fillColor), "background solid color"));
    }
    entries.push_back(makeEntry("wallpaper", "directories", tr("settings.wallpaper-directory"),
                                tr("settings.wallpaper-directory-desc"), {"wallpaper", "directory"},
                                TextSetting{cfg.wallpaper.directory, "~/Pictures/Wallpapers"}, "folder path"));
    entries.push_back(makeEntry("wallpaper", "directories", tr("settings.wallpaper-directory-light"),
                                tr("settings.wallpaper-directory-light-desc"), {"wallpaper", "directory_light"},
                                TextSetting{cfg.wallpaper.directoryLight, ""}, "folder path light theme", true));
    entries.push_back(makeEntry("wallpaper", "directories", tr("settings.wallpaper-directory-dark"),
                                tr("settings.wallpaper-directory-dark-desc"), {"wallpaper", "directory_dark"},
                                TextSetting{cfg.wallpaper.directoryDark, ""}, "folder path dark theme", true));
    {
      MultiSelectSetting transitions;
      transitions.options.reserve(std::size(kWallpaperTransitions));
      for (const auto& opt : kWallpaperTransitions) {
        transitions.options.push_back(SelectOption{std::string(opt.key), tr(opt.labelKey)});
      }
      transitions.selectedValues.reserve(cfg.wallpaper.transitions.size());
      for (const auto& t : cfg.wallpaper.transitions) {
        transitions.selectedValues.emplace_back(enumToKey(kWallpaperTransitions, t));
      }
      transitions.requireAtLeastOne = true;
      entries.push_back(makeEntry("wallpaper", "transition", tr("settings.wallpaper-transitions"),
                                  tr("settings.wallpaper-transitions-desc"), {"wallpaper", "transition"},
                                  std::move(transitions), "effects animation pool"));
    }
    entries.push_back(makeEntry("wallpaper", "transition", tr("settings.wallpaper-transition-duration"),
                                tr("settings.wallpaper-transition-duration-desc"), {"wallpaper", "transition_duration"},
                                SliderSetting{cfg.wallpaper.transitionDurationMs, 100.0f, 30000.0f, 100.0f, true},
                                "fade animation"));
    entries.push_back(makeEntry("wallpaper", "transition", tr("settings.wallpaper-edge-smoothness"),
                                tr("settings.wallpaper-edge-smoothness-desc"), {"wallpaper", "edge_smoothness"},
                                SliderSetting{cfg.wallpaper.edgeSmoothness, 0.0f, 1.0f, 0.01f, false},
                                "transition feathering", true));
    entries.push_back(makeEntry("wallpaper", "automation", tr("settings.wallpaper-automation"),
                                tr("settings.wallpaper-automation-desc"), {"wallpaper", "automation", "enabled"},
                                ToggleSetting{cfg.wallpaper.automation.enabled}, "rotate slideshow"));
    entries.push_back(makeEntry(
        "wallpaper", "automation", tr("settings.wallpaper-automation-interval"),
        tr("settings.wallpaper-automation-interval-desc"), {"wallpaper", "automation", "interval_minutes"},
        SliderSetting{static_cast<float>(cfg.wallpaper.automation.intervalMinutes), 0.0f, 1440.0f, 1.0f, true},
        "rotate slideshow"));
    entries.push_back(makeEntry("wallpaper", "automation", tr("settings.wallpaper-automation-order"),
                                tr("settings.wallpaper-automation-order-desc"), {"wallpaper", "automation", "order"},
                                enumSelect(kWallpaperAutomationOrders, cfg.wallpaper.automation.order),
                                "rotate slideshow"));
    entries.push_back(makeEntry("wallpaper", "automation", tr("settings.wallpaper-automation-recursive"),
                                tr("settings.wallpaper-automation-recursive-desc"),
                                {"wallpaper", "automation", "recursive"},
                                ToggleSetting{cfg.wallpaper.automation.recursive}, "subdirectories", true));

    // Overview (niri-only: surface only renders when niri's overview IPC is available)
    if (env.niriOverviewSupported) {
      entries.push_back(makeEntry("overview", "general", tr("common.enabled"), tr("settings.overview-enabled-desc"),
                                  {"overview", "enabled"}, ToggleSetting{cfg.overview.enabled}, "wallpaper backdrop"));
      entries.push_back(makeEntry("overview", "general", tr("settings.unload-when-hidden"),
                                  tr("settings.unload-when-hidden-desc"), {"overview", "unload_when_not_in_use"},
                                  ToggleSetting{cfg.overview.unloadWhenNotInUse}, "memory"));
      entries.push_back(makeEntry("overview", "backdrop", tr("settings.blur-intensity"),
                                  tr("settings.overview-blur-desc"), {"overview", "blur_intensity"},
                                  SliderSetting{cfg.overview.blurIntensity, 0.0f, 1.0f, 0.01f, false}, "wallpaper"));
      entries.push_back(makeEntry("overview", "backdrop", tr("settings.tint-intensity"),
                                  tr("settings.overview-tint-desc"), {"overview", "tint_intensity"},
                                  SliderSetting{cfg.overview.tintIntensity, 0.0f, 1.0f, 0.01f, false}, "wallpaper"));
    }

    // Templates
    entries.push_back(makeEntry("templates", "built-in", tr("settings.templates-enable-builtins"),
                                tr("settings.templates-enable-builtins-desc"),
                                {"theme", "templates", "enable_builtins"},
                                ToggleSetting{cfg.theme.templates.enableBuiltins}, "theme templates"));
    {
      const auto availableTemplates = noctalia::theme::availableTemplates();
      std::vector<SelectOption> templateOptions;
      templateOptions.reserve(availableTemplates.size());
      for (const auto& t : availableTemplates) {
        templateOptions.push_back(SelectOption{t.id, t.displayName});
      }
      entries.push_back(makeEntry(
          "templates", "built-in", tr("settings.templates-builtin-ids"), tr("settings.templates-builtin-ids-desc"),
          {"theme", "templates", "builtin_ids"},
          ListSetting{.items = cfg.theme.templates.builtinIds, .suggestedOptions = std::move(templateOptions)},
          "theme templates apps foot walker gtk"));
    }
    entries.push_back(makeEntry("templates", "user", tr("settings.templates-enable-user-templates"),
                                tr("settings.templates-enable-user-templates-desc"),
                                {"theme", "templates", "enable_user_templates"},
                                ToggleSetting{cfg.theme.templates.enableUserTemplates}, "theme templates user custom"));
    entries.push_back(makeEntry("templates", "user", tr("settings.templates-user-config"),
                                tr("settings.templates-user-config-desc"), {"theme", "templates", "user_config"},
                                TextSetting{cfg.theme.templates.userConfig, "~/.config/noctalia/user-templates.toml"},
                                "theme templates path file", true));

    // Dock
    entries.push_back(makeEntry("dock", "general", tr("common.enabled"), tr("settings.dock-enabled-desc"),
                                {"dock", "enabled"}, ToggleSetting{cfg.dock.enabled}, "launcher apps"));
    entries.push_back(makeEntry("dock", "general", tr("settings.active-monitor-only"),
                                tr("settings.active-monitor-only-desc"), {"dock", "active_monitor_only"},
                                ToggleSetting{cfg.dock.activeMonitorOnly}, "monitor"));
    entries.push_back(makeEntry("dock", "layout", tr("common.position"), tr("settings.dock-position-desc"),
                                {"dock", "position"}, positionSelect(cfg.dock.position), "edge"));
    entries.push_back(
        makeEntry("dock", "layout", tr("settings.icon-size"), tr("settings.icon-size-desc"), {"dock", "icon_size"},
                  SliderSetting{static_cast<float>(cfg.dock.iconSize), 16.0f, 128.0f, 1.0f, true}, "apps"));
    entries.push_back(
        makeEntry("dock", "layout", tr("common.padding"), tr("settings.dock-padding-desc"), {"dock", "padding"},
                  SliderSetting{static_cast<float>(cfg.dock.padding), 0.0f, 100.0f, 1.0f, true}, "inset"));
    entries.push_back(makeEntry(
        "dock", "layout", tr("settings.item-spacing"), tr("settings.item-spacing-desc"), {"dock", "item_spacing"},
        SliderSetting{static_cast<float>(cfg.dock.itemSpacing), 0.0f, 100.0f, 1.0f, true}, "gap"));
    entries.push_back(makeEntry(
        "dock", "layout", tr("common.horizontal-margin"), tr("settings.dock-margin-h-desc"), {"dock", "margin_h"},
        SliderSetting{static_cast<float>(cfg.dock.marginH), 0.0f, 500.0f, 1.0f, true}, "gap inset"));
    entries.push_back(makeEntry(
        "dock", "layout", tr("common.vertical-margin"), tr("settings.dock-margin-v-desc"), {"dock", "margin_v"},
        SliderSetting{static_cast<float>(cfg.dock.marginV), 0.0f, 100.0f, 1.0f, true}, "gap inset"));
    entries.push_back(
        makeEntry("dock", "shape", tr("common.corner-radius"), tr("settings.dock-radius-desc"), {"dock", "radius"},
                  SliderSetting{static_cast<float>(cfg.dock.radius), 0.0f, 80.0f, 1.0f, true}, "rounded"));
    entries.push_back(makeEntry("dock", "shape", tr("common.background-opacity"), tr("settings.dock-bg-opacity-desc"),
                                {"dock", "background_opacity"},
                                SliderSetting{cfg.dock.backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "alpha"));
    entries.push_back(makeEntry("dock", "effects", tr("common.background-blur"), tr("settings.dock-bg-blur-desc"),
                                {"dock", "background_blur"}, ToggleSetting{cfg.dock.backgroundBlur}, "blur"));
    entries.push_back(makeEntry("dock", "effects", tr("common.shadow"), tr("settings.dock-shadow-desc"),
                                {"dock", "shadow"}, ToggleSetting{cfg.dock.shadow}, "shadow"));
    entries.push_back(makeEntry("dock", "behavior", tr("common.auto-hide"), tr("settings.dock-auto-hide-desc"),
                                {"dock", "auto_hide"}, ToggleSetting{cfg.dock.autoHide}, "autohide"));
    entries.push_back(makeEntry("dock", "behavior", tr("common.reserve-space"), tr("settings.dock-reserve-space-desc"),
                                {"dock", "reserve_space"}, ToggleSetting{cfg.dock.reserveSpace}, "exclusive zone"));
    entries.push_back(makeEntry("dock", "behavior", tr("settings.show-running"), tr("settings.show-running-desc"),
                                {"dock", "show_running"}, ToggleSetting{cfg.dock.showRunning}, "windows"));
    entries.push_back(makeEntry("dock", "behavior", tr("settings.show-instance-count"),
                                tr("settings.show-instance-count-desc"), {"dock", "show_instance_count"},
                                ToggleSetting{cfg.dock.showInstanceCount}, "badge windows"));
    entries.push_back(makeEntry("dock", "focus-styling", tr("settings.active-icon-scale"),
                                tr("settings.active-icon-scale-desc"), {"dock", "active_scale"},
                                SliderSetting{cfg.dock.activeScale, 0.1f, 1.75f, 0.05f, false}, "focused", true));
    entries.push_back(makeEntry("dock", "focus-styling", tr("settings.inactive-icon-scale"),
                                tr("settings.inactive-icon-scale-desc"), {"dock", "inactive_scale"},
                                SliderSetting{cfg.dock.inactiveScale, 0.1f, 1.0f, 0.05f, false}, "unfocused", true));
    entries.push_back(makeEntry("dock", "focus-styling", tr("settings.active-icon-opacity"),
                                tr("settings.active-icon-opacity-desc"), {"dock", "active_opacity"},
                                SliderSetting{cfg.dock.activeOpacity, 0.0f, 1.0f, 0.01f, false}, "focused alpha",
                                true));
    entries.push_back(makeEntry("dock", "focus-styling", tr("settings.inactive-icon-opacity"),
                                tr("settings.inactive-icon-opacity-desc"), {"dock", "inactive_opacity"},
                                SliderSetting{cfg.dock.inactiveOpacity, 0.0f, 1.0f, 0.01f, false}, "unfocused alpha",
                                true));
    entries.push_back(makeEntry("dock", "pinned-apps", tr("settings.pinned-apps"), tr("settings.pinned-apps-desc"),
                                {"dock", "pinned"}, ListSetting{.items = cfg.dock.pinned}, "favorites"));

    // Desktop
    entries.push_back(makeEntry("desktop", "widgets", tr("settings.desktop-widgets"),
                                tr("settings.desktop-widgets-desc"), {"desktop_widgets", "enabled"},
                                ToggleSetting{cfg.desktopWidgets.enabled}, "desktop"));

    // Shell
    entries.push_back(makeEntry("shell", "profile", tr("settings.avatar-path"), tr("settings.avatar-path-desc"),
                                {"shell", "avatar_path"}, TextSetting{cfg.shell.avatarPath, ""}, "image picture"));
    entries.push_back(makeEntry("shell", "network", tr("settings.offline-mode"), tr("settings.offline-mode-desc"),
                                {"shell", "offline_mode"}, ToggleSetting{cfg.shell.offlineMode},
                                "network http fetch download"));
    entries.push_back(makeEntry("shell", "network", tr("settings.telemetry"), tr("settings.telemetry-desc"),
                                {"shell", "telemetry_enabled"}, ToggleSetting{cfg.shell.telemetryEnabled},
                                "analytics ping privacy"));
    entries.push_back(makeEntry("shell", "security", tr("settings.polkit-agent"), tr("settings.polkit-agent-desc"),
                                {"shell", "polkit_agent"}, ToggleSetting{cfg.shell.polkitAgent}, "auth password"));
    entries.push_back(makeEntry("shell", "security", tr("settings.password-style"), tr("settings.password-style-desc"),
                                {"shell", "password_style"},
                                enumSelect(kPasswordMaskStyles, cfg.shell.passwordMaskStyle), "polkit lock mask"));
    entries.push_back(makeEntry("shell", "location", tr("settings.show-location"), tr("settings.show-location-desc"),
                                {"shell", "show_location"}, ToggleSetting{cfg.shell.showLocation}, "weather"));
    entries.push_back(makeEntry("shell", "clipboard", tr("settings.clipboard-auto-paste"),
                                tr("settings.clipboard-auto-paste-desc"), {"shell", "clipboard_auto_paste"},
                                enumSelect(kClipboardAutoPasteModes, cfg.shell.clipboardAutoPaste), "clipboard paste"));
    entries.push_back(makeEntry("shell", "osd", tr("settings.osd-position"), tr("settings.osd-position-desc"),
                                {"osd", "position"},
                                plainSelect({{"top_right", "settings.opt.top-right"},
                                             {"top_left", "settings.opt.top-left"},
                                             {"top_center", "settings.opt.top-center"},
                                             {"bottom_right", "settings.opt.bottom-right"},
                                             {"bottom_left", "settings.opt.bottom-left"},
                                             {"bottom_center", "settings.opt.bottom-center"}},
                                            cfg.osd.position),
                                "hud overlay volume brightness"));

    // Services
    entries.push_back(makeEntry("services", "system", tr("settings.system-monitor"), tr("settings.system-monitor-desc"),
                                {"system", "monitor", "enabled"}, ToggleSetting{cfg.system.monitor.enabled},
                                "system monitor cpu ram memory"));
    entries.push_back(makeEntry("services", "weather", tr("settings.weather"), tr("settings.weather-desc"),
                                {"weather", "enabled"}, ToggleSetting{cfg.weather.enabled}, "forecast"));
    entries.push_back(makeEntry("services", "weather", tr("settings.weather-location"),
                                tr("settings.weather-location-desc"), {"weather", "auto_locate"},
                                ToggleSetting{cfg.weather.autoLocate}, "forecast gps"));
    entries.push_back(makeEntry(
        "services", "weather", tr("settings.weather-unit"), tr("settings.weather-unit-desc"), {"weather", "unit"},
        plainSelect({{"celsius", "settings.opt.celsius"}, {"fahrenheit", "settings.opt.fahrenheit"}}, cfg.weather.unit),
        "temperature"));
    entries.push_back(makeEntry("services", "weather", tr("settings.weather-address"),
                                tr("settings.weather-address-desc"), {"weather", "address"},
                                TextSetting{cfg.weather.address, "City, Country"}, "location"));
    entries.push_back(makeEntry("services", "weather", tr("settings.weather-effects"),
                                tr("settings.weather-effects-desc"), {"weather", "effects"},
                                ToggleSetting{cfg.weather.effects}, "forecast visuals"));
    entries.push_back(makeEntry("services", "weather", tr("settings.refresh-interval"),
                                tr("settings.refresh-interval-desc"), {"weather", "refresh_minutes"},
                                SliderSetting{static_cast<float>(cfg.weather.refreshMinutes), 5.0f, 240.0f, 5.0f, true},
                                "forecast"));
    entries.push_back(makeEntry("services", "audio", tr("settings.audio-overdrive"),
                                tr("settings.audio-overdrive-desc"), {"audio", "enable_overdrive"},
                                ToggleSetting{cfg.audio.enableOverdrive}, "volume"));
    entries.push_back(makeEntry("services", "audio", tr("settings.shell-sounds"), tr("settings.shell-sounds-desc"),
                                {"audio", "enable_sounds"}, ToggleSetting{cfg.audio.enableSounds}, "sound"));
    entries.push_back(makeEntry("services", "audio", tr("settings.sound-volume"), tr("settings.sound-volume-desc"),
                                {"audio", "sound_volume"},
                                SliderSetting{cfg.audio.soundVolume, 0.0f, 1.0f, 0.01f, false}, "sound"));
    entries.push_back(makeEntry("services", "audio", tr("settings.volume-change-sound"),
                                tr("settings.volume-change-sound-desc"), {"audio", "volume_change_sound"},
                                TextSetting{cfg.audio.volumeChangeSound, ""}, "sound path file", true));
    entries.push_back(makeEntry("services", "audio", tr("settings.notification-sound"),
                                tr("settings.notification-sound-desc"), {"audio", "notification_sound"},
                                TextSetting{cfg.audio.notificationSound, ""}, "sound path file", true));
    entries.push_back(makeEntry("services", "brightness", tr("settings.ddcutil"), tr("settings.ddcutil-desc"),
                                {"brightness", "enable_ddcutil"}, ToggleSetting{cfg.brightness.enableDdcutil},
                                "monitor ddcutil"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.night-light"), tr("settings.night-light-desc"),
                                {"nightlight", "enabled"}, ToggleSetting{cfg.nightlight.enabled}, "wlsunset"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.force-night-light"),
                                tr("settings.force-night-light-desc"), {"nightlight", "force"},
                                ToggleSetting{cfg.nightlight.force}, "wlsunset"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.use-weather-location"),
                                tr("settings.use-weather-location-desc"), {"nightlight", "use_weather_location"},
                                ToggleSetting{cfg.nightlight.useWeatherLocation}, "location"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.night-light-start-time"),
                                tr("settings.night-light-start-time-desc"), {"nightlight", "start_time"},
                                TextSetting{cfg.nightlight.startTime, "20:30"}, "time schedule sunset"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.night-light-stop-time"),
                                tr("settings.night-light-stop-time-desc"), {"nightlight", "stop_time"},
                                TextSetting{cfg.nightlight.stopTime, "07:30"}, "time schedule sunrise"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.latitude"), tr("settings.latitude-desc"),
                                {"nightlight", "latitude"},
                                OptionalNumberSetting{cfg.nightlight.latitude, -90.0, 90.0, "52.5200"},
                                "coordinate location sunrise sunset", true));
    entries.push_back(makeEntry("services", "night-light", tr("settings.longitude"), tr("settings.longitude-desc"),
                                {"nightlight", "longitude"},
                                OptionalNumberSetting{cfg.nightlight.longitude, -180.0, 180.0, "13.4050"},
                                "coordinate location sunrise sunset", true));
    entries.push_back(
        makeEntry("services", "night-light", tr("settings.day-temperature"), tr("settings.day-temperature-desc"),
                  {"nightlight", "temperature_day"},
                  SliderSetting{static_cast<float>(cfg.nightlight.dayTemperature), 1000.0f, 10000.0f, 100.0f, true},
                  "wlsunset kelvin"));
    entries.push_back(
        makeEntry("services", "night-light", tr("settings.night-temperature"), tr("settings.night-temperature-desc"),
                  {"nightlight", "temperature_night"},
                  SliderSetting{static_cast<float>(cfg.nightlight.nightTemperature), 1000.0f, 10000.0f, 100.0f, true},
                  "wlsunset kelvin"));

    // Notifications
    entries.push_back(makeEntry("notifications", "general", tr("settings.notification-daemon"),
                                tr("settings.notification-daemon-desc"), {"notification", "enable_daemon"},
                                ToggleSetting{cfg.notification.enableDaemon}, "dbus"));
    entries.push_back(makeEntry("notifications", "toasts", tr("settings.toast-blur"), tr("settings.toast-blur-desc"),
                                {"notification", "background_blur"}, ToggleSetting{cfg.notification.backgroundBlur},
                                "popup"));
    entries.push_back(makeEntry("notifications", "toasts", tr("settings.notification-position"),
                                tr("settings.notification-position-desc"), {"notification", "position"},
                                plainSelect({{"top_right", "settings.opt.top-right"},
                                             {"top_left", "settings.opt.top-left"},
                                             {"top_center", "settings.opt.top-center"},
                                             {"bottom_right", "settings.opt.bottom-right"},
                                             {"bottom_left", "settings.opt.bottom-left"},
                                             {"bottom_center", "settings.opt.bottom-center"}},
                                            cfg.notification.position),
                                "toast popup placement anchor"));
    entries.push_back(makeEntry("notifications", "toasts", tr("settings.toast-opacity"),
                                tr("settings.toast-opacity-desc"), {"notification", "background_opacity"},
                                SliderSetting{cfg.notification.backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "popup"));

    // Bar
    if (selectedBar != nullptr && selectedMonitorOverride == nullptr) {
      const std::string section = "bar";
      const std::vector<std::string> root = {"bar", selectedBar->name};
      auto path = [&](std::string key) {
        std::vector<std::string> p = root;
        p.push_back(std::move(key));
        return p;
      };
      entries.push_back(makeEntry(section, "general", tr("common.enabled"), tr("settings.bar-enabled-desc"),
                                  path("enabled"), ToggleSetting{selectedBar->enabled}, "visible"));
      entries.push_back(makeEntry(section, "general", tr("common.position"), tr("settings.bar-position-desc"),
                                  path("position"), positionSelect(selectedBar->position), "edge"));
      entries.push_back(makeEntry(section, "general", tr("common.auto-hide"), tr("settings.bar-auto-hide-desc"),
                                  path("auto_hide"), ToggleSetting{selectedBar->autoHide}, "autohide"));
      entries.push_back(makeEntry(section, "general", tr("common.reserve-space"), tr("settings.bar-reserve-space-desc"),
                                  path("reserve_space"), ToggleSetting{selectedBar->reserveSpace}, "exclusive zone"));
      entries.push_back(makeEntry(
          section, "layout", tr("settings.thickness"), tr("settings.thickness-desc"), path("thickness"),
          SliderSetting{static_cast<float>(selectedBar->thickness), 10.0f, 120.0f, 1.0f, true}, "height width"));
      entries.push_back(makeEntry(section, "layout", tr("settings.content-scale"), tr("settings.content-scale-desc"),
                                  path("scale"), SliderSetting{selectedBar->scale, 0.5f, 4.0f, 0.05f, false},
                                  "zoom size"));
      entries.push_back(makeEntry(
          section, "layout", tr("common.horizontal-margin"), tr("settings.bar-margin-h-desc"), path("margin_h"),
          SliderSetting{static_cast<float>(selectedBar->marginH), 0.0f, 500.0f, 1.0f, true}, "gap inset"));
      entries.push_back(
          makeEntry(section, "layout", tr("common.vertical-margin"), tr("settings.bar-margin-v-desc"), path("margin_v"),
                    SliderSetting{static_cast<float>(selectedBar->marginV), 0.0f, 100.0f, 1.0f, true}, "gap inset"));
      entries.push_back(makeEntry(
          section, "layout", tr("settings.content-padding"), tr("settings.content-padding-desc"), path("padding"),
          SliderSetting{static_cast<float>(selectedBar->padding), 0.0f, 80.0f, 1.0f, true}, "inset"));
      entries.push_back(
          makeEntry(section, "shape", tr("common.corner-radius"), tr("settings.bar-radius-desc"), path("radius"),
                    SliderSetting{static_cast<float>(selectedBar->radius), 0.0f, 80.0f, 1.0f, true}, "rounded"));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.corner-top-left"), tr("settings.corner-top-left-desc"),
                    path("radius_top_left"),
                    SliderSetting{static_cast<float>(selectedBar->radiusTopLeft), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.corner-top-right"), tr("settings.corner-top-right-desc"),
                    path("radius_top_right"),
                    SliderSetting{static_cast<float>(selectedBar->radiusTopRight), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.corner-bottom-left"), tr("settings.corner-bottom-left-desc"),
                    path("radius_bottom_left"),
                    SliderSetting{static_cast<float>(selectedBar->radiusBottomLeft), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.corner-bottom-right"), tr("settings.corner-bottom-right-desc"),
                    path("radius_bottom_right"),
                    SliderSetting{static_cast<float>(selectedBar->radiusBottomRight), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(makeEntry(section, "shape", tr("common.background-opacity"), tr("settings.bar-bg-opacity-desc"),
                                  path("background_opacity"),
                                  SliderSetting{selectedBar->backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "alpha"));
      entries.push_back(makeEntry(section, "effects", tr("common.background-blur"), tr("settings.bar-bg-blur-desc"),
                                  path("background_blur"), ToggleSetting{selectedBar->backgroundBlur}, "blur"));
      entries.push_back(makeEntry(section, "effects", tr("common.shadow"), tr("settings.bar-shadow-desc"),
                                  path("shadow"), ToggleSetting{selectedBar->shadow}, "shadow"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.widget-capsules"),
                                  tr("settings.widget-capsules-desc"), path("capsule"),
                                  ToggleSetting{selectedBar->widgetCapsuleDefault}, "pill"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.widget-color"), tr("settings.widget-color-desc"),
                                  path("color"), optionalColorRoleSelect(selectedBar->widgetColor),
                                  "theme role foreground", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.capsule-fill"), tr("settings.capsule-fill-desc"),
                                  path("capsule_fill"), colorRoleSelect(selectedBar->widgetCapsuleFill),
                                  "theme role pill", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.capsule-foreground"),
                                  tr("settings.capsule-foreground-desc"), path("capsule_foreground"),
                                  optionalColorRoleSelect(selectedBar->widgetCapsuleForeground),
                                  "theme role foreground pill", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.capsule-border"), tr("settings.capsule-border-desc"),
                                  path("capsule_border"), capsuleBorderRoleSelect(selectedBar->widgetCapsuleBorder),
                                  "theme role pill outline", true));
      entries.push_back(makeEntry(
          section, "widgets", tr("settings.widget-spacing"), tr("settings.widget-spacing-desc"), path("widget_spacing"),
          SliderSetting{static_cast<float>(selectedBar->widgetSpacing), 0.0f, 32.0f, 1.0f, true}, "gap"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.capsule-padding"),
                                  tr("settings.capsule-padding-desc"), path("capsule_padding"),
                                  SliderSetting{selectedBar->widgetCapsulePadding, 0.0f, 48.0f, 1.0f, false},
                                  "pill inset", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.capsule-opacity"),
                                  tr("settings.capsule-opacity-desc"), path("capsule_opacity"),
                                  SliderSetting{selectedBar->widgetCapsuleOpacity, 0.0f, 1.0f, 0.01f, false},
                                  "pill alpha", true));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.start-widgets"),
                                  tr("settings.start-widgets-desc"), path("start"),
                                  ListSetting{.items = selectedBar->startWidgets}, "left"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.center-widgets"),
                                  tr("settings.center-widgets-desc"), path("center"),
                                  ListSetting{.items = selectedBar->centerWidgets}, "middle"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.end-widgets"), tr("settings.end-widgets-desc"),
                                  path("end"), ListSetting{.items = selectedBar->endWidgets}, "right"));
    }

    // Bar monitor override
    if (selectedBar != nullptr && selectedMonitorOverride != nullptr) {
      const auto& ovr = *selectedMonitorOverride;
      const auto& bar = *selectedBar;
      const std::string section = "bar";
      const std::vector<std::string> root = {"bar", bar.name, "monitor", ovr.match};
      auto mpath = [&](std::string key) {
        std::vector<std::string> p = root;
        p.push_back(std::move(key));
        return p;
      };

      entries.push_back(makeEntry(section, "general", tr("common.enabled"), tr("settings.bar-enabled-desc"),
                                  mpath("enabled"), ToggleSetting{ovr.enabled.value_or(bar.enabled)}, "visible"));
      entries.push_back(makeEntry(section, "general", tr("common.auto-hide"), tr("settings.bar-auto-hide-desc"),
                                  mpath("auto_hide"), ToggleSetting{ovr.autoHide.value_or(bar.autoHide)}, "autohide"));
      entries.push_back(makeEntry(section, "general", tr("common.reserve-space"), tr("settings.bar-reserve-space-desc"),
                                  mpath("reserve_space"), ToggleSetting{ovr.reserveSpace.value_or(bar.reserveSpace)},
                                  "exclusive zone"));
      entries.push_back(
          makeEntry(section, "layout", tr("settings.thickness"), tr("settings.thickness-desc"), mpath("thickness"),
                    SliderSetting{static_cast<float>(ovr.thickness.value_or(bar.thickness)), 10.0f, 120.0f, 1.0f, true},
                    "height width"));
      entries.push_back(makeEntry(section, "layout", tr("settings.content-scale"), tr("settings.content-scale-desc"),
                                  mpath("scale"),
                                  SliderSetting{ovr.scale.value_or(bar.scale), 0.5f, 4.0f, 0.05f, false}, "zoom size"));
      entries.push_back(makeEntry(
          section, "layout", tr("common.horizontal-margin"), tr("settings.bar-margin-h-desc"), mpath("margin_h"),
          SliderSetting{static_cast<float>(ovr.marginH.value_or(bar.marginH)), 0.0f, 500.0f, 1.0f, true}, "gap inset"));
      entries.push_back(makeEntry(
          section, "layout", tr("common.vertical-margin"), tr("settings.bar-margin-v-desc"), mpath("margin_v"),
          SliderSetting{static_cast<float>(ovr.marginV.value_or(bar.marginV)), 0.0f, 100.0f, 1.0f, true}, "gap inset"));
      entries.push_back(makeEntry(
          section, "layout", tr("settings.content-padding"), tr("settings.content-padding-desc"), mpath("padding"),
          SliderSetting{static_cast<float>(ovr.padding.value_or(bar.padding)), 0.0f, 80.0f, 1.0f, true}, "inset"));
      entries.push_back(makeEntry(
          section, "shape", tr("common.corner-radius"), tr("settings.bar-radius-desc"), mpath("radius"),
          SliderSetting{static_cast<float>(ovr.radius.value_or(bar.radius)), 0.0f, 80.0f, 1.0f, true}, "rounded"));
      entries.push_back(makeEntry(
          section, "shape", tr("settings.corner-top-left"), tr("settings.corner-top-left-desc"),
          mpath("radius_top_left"),
          SliderSetting{static_cast<float>(ovr.radiusTopLeft.value_or(bar.radiusTopLeft)), 0.0f, 80.0f, 1.0f, true},
          "rounded corner", true));
      entries.push_back(makeEntry(
          section, "shape", tr("settings.corner-top-right"), tr("settings.corner-top-right-desc"),
          mpath("radius_top_right"),
          SliderSetting{static_cast<float>(ovr.radiusTopRight.value_or(bar.radiusTopRight)), 0.0f, 80.0f, 1.0f, true},
          "rounded corner", true));
      entries.push_back(makeEntry(section, "shape", tr("settings.corner-bottom-left"),
                                  tr("settings.corner-bottom-left-desc"), mpath("radius_bottom_left"),
                                  SliderSetting{static_cast<float>(ovr.radiusBottomLeft.value_or(bar.radiusBottomLeft)),
                                                0.0f, 80.0f, 1.0f, true},
                                  "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.corner-bottom-right"), tr("settings.corner-bottom-right-desc"),
                    mpath("radius_bottom_right"),
                    SliderSetting{static_cast<float>(ovr.radiusBottomRight.value_or(bar.radiusBottomRight)), 0.0f,
                                  80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(makeEntry(
          section, "shape", tr("common.background-opacity"), tr("settings.bar-bg-opacity-desc"),
          mpath("background_opacity"),
          SliderSetting{ovr.backgroundOpacity.value_or(bar.backgroundOpacity), 0.0f, 1.0f, 0.01f, false}, "alpha"));
      entries.push_back(makeEntry(section, "effects", tr("common.background-blur"), tr("settings.bar-bg-blur-desc"),
                                  mpath("background_blur"),
                                  ToggleSetting{ovr.backgroundBlur.value_or(bar.backgroundBlur)}, "blur"));
      entries.push_back(makeEntry(section, "effects", tr("common.shadow"), tr("settings.bar-shadow-desc"),
                                  mpath("shadow"), ToggleSetting{ovr.shadow.value_or(bar.shadow)}, "shadow"));
      entries.push_back(makeEntry(
          section, "widgets", tr("settings.widget-spacing"), tr("settings.widget-spacing-desc"),
          mpath("widget_spacing"),
          SliderSetting{static_cast<float>(ovr.widgetSpacing.value_or(bar.widgetSpacing)), 0.0f, 32.0f, 1.0f, true},
          "gap"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.widget-capsules"),
                                  tr("settings.widget-capsules-desc"), mpath("capsule"),
                                  ToggleSetting{ovr.widgetCapsuleDefault.value_or(bar.widgetCapsuleDefault)}, "pill"));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.widget-color"), tr("settings.widget-color-desc"), mpath("color"),
                    optionalColorRoleSelect(ovr.widgetColor.has_value() ? ovr.widgetColor : bar.widgetColor),
                    "theme role foreground", true));
      entries.push_back(makeEntry(
          section, "widgets", tr("settings.capsule-fill"), tr("settings.capsule-fill-desc"), mpath("capsule_fill"),
          colorRoleSelect(ovr.widgetCapsuleFill.value_or(bar.widgetCapsuleFill)), "theme role pill", true));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.capsule-foreground"), tr("settings.capsule-foreground-desc"),
                    mpath("capsule_foreground"),
                    optionalColorRoleSelect(ovr.widgetCapsuleForeground.has_value() ? ovr.widgetCapsuleForeground
                                                                                    : bar.widgetCapsuleForeground),
                    "theme role foreground pill", true));
      entries.push_back(makeEntry(
          section, "widgets", tr("settings.capsule-border"), tr("settings.capsule-border-desc"),
          mpath("capsule_border"),
          capsuleBorderRoleSelect(ovr.widgetCapsuleBorderSpecified ? ovr.widgetCapsuleBorder : bar.widgetCapsuleBorder),
          "theme role pill outline", true));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.capsule-padding"), tr("settings.capsule-padding-desc"),
                    mpath("capsule_padding"),
                    SliderSetting{static_cast<float>(ovr.widgetCapsulePadding.value_or(bar.widgetCapsulePadding)), 0.0f,
                                  48.0f, 1.0f, false},
                    "pill inset", true));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.capsule-opacity"), tr("settings.capsule-opacity-desc"),
                    mpath("capsule_opacity"),
                    SliderSetting{static_cast<float>(ovr.widgetCapsuleOpacity.value_or(bar.widgetCapsuleOpacity)), 0.0f,
                                  1.0f, 0.01f, false},
                    "pill alpha", true));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.start-widgets"),
                                  tr("settings.start-widgets-desc"), mpath("start"),
                                  ListSetting{.items = ovr.startWidgets.value_or(bar.startWidgets)}, "left"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.center-widgets"),
                                  tr("settings.center-widgets-desc"), mpath("center"),
                                  ListSetting{.items = ovr.centerWidgets.value_or(bar.centerWidgets)}, "middle"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.end-widgets"), tr("settings.end-widgets-desc"),
                                  mpath("end"), ListSetting{.items = ovr.endWidgets.value_or(bar.endWidgets)},
                                  "right"));
    }

    return entries;
  }

} // namespace settings
