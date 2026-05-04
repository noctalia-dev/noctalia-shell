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

    SelectSetting asSegmented(SelectSetting setting) {
      setting.segmented = true;
      return setting;
    }

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
      opts.push_back(SelectOption{"", i18n::tr("common.states.auto")});
      for (const auto& language : i18n::kSupportedLanguages) {
        opts.push_back(SelectOption{std::string(language.code), std::string(language.displayName)});
      }
      return SelectSetting{std::move(opts), std::string(selected)};
    }

    std::string colorRoleValue(const ColorSpec& color) {
      if (color.role.has_value()) {
        return std::string(colorRoleToken(*color.role));
      }
      return {};
    }

    std::string optionalColorRoleValue(const std::optional<ColorSpec>& color) {
      if (color.has_value()) {
        return colorRoleValue(*color);
      }
      return {};
    }

    std::vector<ColorRole> allColorRoles() {
      std::vector<ColorRole> roles;
      roles.reserve(kColorRoleTokens.size());
      for (const auto& token : kColorRoleTokens) {
        roles.push_back(token.role);
      }
      return roles;
    }

    ColorRolePickerSetting colorRolePicker(const ColorSpec& selected) {
      return ColorRolePickerSetting{allColorRoles(), colorRoleValue(selected)};
    }

    ColorRolePickerSetting optionalColorRolePicker(const std::optional<ColorSpec>& selected) {
      return ColorRolePickerSetting{allColorRoles(), optionalColorRoleValue(selected), true};
    }

    ColorRolePickerSetting capsuleBorderRolePicker(const std::optional<ColorSpec>& selected) {
      return ColorRolePickerSetting{allColorRoles(), optionalColorRoleValue(selected), true};
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

  std::string normalizedSettingQuery(std::string_view query) { return lower(query); }

  bool matchesNormalizedSettingQuery(const SettingEntry& entry, std::string_view normalizedQuery) {
    if (normalizedQuery.empty()) {
      return true;
    }
    return entry.searchText.find(normalizedQuery) != std::string::npos;
  }

  bool matchesSettingQuery(const SettingEntry& entry, std::string_view query) {
    return matchesNormalizedSettingQuery(entry, normalizedSettingQuery(query));
  }

  std::string_view sectionGlyph(std::string_view section) {
    if (section == "appearance")
      return "adjustments-horizontal";
    if (section == "templates")
      return "color-swatch";
    if (section == "shell")
      return "app-window";
    if (section == "dock")
      return "layout-bottombar";
    if (section == "backdrop")
      return "niri";
    if (section == "wallpaper")
      return "paint";
    if (section == "desktop")
      return "layout-board";
    if (section == "services")
      return "stack-2";
    if (section == "notifications")
      return "bell";
    if (section == "bar")
      return "bar";
    return "settings";
  }

  // V4 REF.
  // "settings-general": "adjustments-horizontal",
  // "settings-bar": "crop-16-9",
  // "settings-user-interface": "layout-board",
  // "settings-control-center": "adjustments-horizontal",
  // "settings-dock": "layout-bottombar",
  // "settings-launcher": "rocket",
  // "settings-audio": "device-speaker",
  // "settings-display": "device-desktop",
  // "settings-network": "circles-relation",
  // "settings-brightness": "brightness-up",
  // "settings-location": "world-pin",
  // "settings-color-scheme": "palette",
  // "settings-wallpaper": "paint",
  // "settings-wallpaper-selector": "library-photo",
  // "settings-hooks": "link",
  // "settings-notifications": "bell",
  // "settings-osd": "picture-in-picture",
  // "settings-about": "info-square-rounded",
  // "settings-idle": "moon",
  // "settings-lock-screen": "lock",
  // "settings-session-menu": "power",
  // "settings-system-monitor": "activity",

  std::vector<SettingEntry> buildSettingsRegistry(const Config& cfg, const BarConfig* selectedBar,
                                                  const BarMonitorOverride* selectedMonitorOverride,
                                                  const RegistryEnvironment& env) {
    using i18n::tr;
    const auto positionSelect = [](std::string_view selected) {
      return asSegmented(plainSelect({{"top", "settings.options.edge.top"},
                                      {"bottom", "settings.options.edge.bottom"},
                                      {"left", "settings.options.edge.left"},
                                      {"right", "settings.options.edge.right"}},
                                     selected));
    };
    std::vector<SettingEntry> entries;

    // Appearance
    entries.push_back(makeEntry("appearance", "theme", tr("settings.schema.appearance.theme-mode.label"),
                                tr("settings.schema.appearance.theme-mode.description"), {"theme", "mode"},
                                asSegmented(enumSelect(kThemeModes, cfg.theme.mode)), "dark light auto colors"));
    entries.push_back(makeEntry("appearance", "theme", tr("settings.schema.appearance.theme-source.label"),
                                tr("settings.schema.appearance.theme-source.description"), {"theme", "source"},
                                asSegmented(enumSelect(kThemeSources, cfg.theme.source)), "palette colors"));
    if (cfg.theme.source == ThemeSource::Builtin) {
      entries.push_back(makeEntry("appearance", "theme", tr("settings.schema.appearance.theme-palette.label"),
                                  tr("settings.schema.appearance.theme-palette.description"), {"theme", "builtin"},
                                  builtinPaletteSelect(cfg.theme.builtinPalette), "builtin palette colors"));
    } else if (cfg.theme.source == ThemeSource::Wallpaper) {
      entries.push_back(makeEntry("appearance", "theme",
                                  tr("settings.schema.appearance.wallpaper-generation-scheme.label"),
                                  tr("settings.schema.appearance.wallpaper-generation-scheme.description"),
                                  {"theme", "wallpaper_scheme"}, wallpaperSchemeSelect(cfg.theme.wallpaperScheme),
                                  "wallpaper palette generator scheme material you m3 colors"));
    } else if (cfg.theme.source == ThemeSource::Community) {
      SettingControl communityPaletteControl = TextSetting{cfg.theme.communityPalette, "Oxocarbon"};
      if (!env.communityPalettes.empty()) {
        communityPaletteControl = SearchPickerSetting{
            .options = env.communityPalettes,
            .selectedValue = cfg.theme.communityPalette,
            .placeholder = tr("settings.schema.appearance.community-palette.search-placeholder"),
            .emptyText = tr("ui.controls.search-picker.empty"),
            .preferredHeight = 240.0f,
        };
      }
      entries.push_back(makeEntry("appearance", "theme", tr("settings.schema.appearance.community-palette.label"),
                                  tr("settings.schema.appearance.community-palette.description"),
                                  {"theme", "community_palette"}, std::move(communityPaletteControl),
                                  "community palette colors"));
    }
    entries.push_back(makeEntry("appearance", "interface", tr("settings.schema.appearance.ui-scale.label"),
                                tr("settings.schema.appearance.ui-scale.description"), {"shell", "ui_scale"},
                                SliderSetting{cfg.shell.uiScale, 0.5f, 2.5f, 0.05f, false}, "size"));
    entries.push_back(makeEntry("appearance", "interface", tr("settings.schema.appearance.font-family.label"),
                                tr("settings.schema.appearance.font-family.description"), {"shell", "font_family"},
                                TextSetting{cfg.shell.fontFamily, "sans-serif"}, "typeface"));
    entries.push_back(makeEntry("appearance", "interface", tr("settings.schema.appearance.language.label"),
                                tr("settings.schema.appearance.language.description"), {"shell", "lang"},
                                languageSelect(cfg.shell.lang), "locale translation", true));
    entries.push_back(makeEntry("appearance", "motion", tr("settings.schema.appearance.animations.label"),
                                tr("settings.schema.appearance.animations.description"),
                                {"shell", "animation", "enabled"}, ToggleSetting{cfg.shell.animation.enabled},
                                "motion"));
    entries.push_back(makeEntry("appearance", "motion", tr("settings.schema.appearance.animation-speed.label"),
                                tr("settings.schema.appearance.animation-speed.description"),
                                {"shell", "animation", "speed"},
                                SliderSetting{cfg.shell.animation.speed, 0.1f, 4.0f, 0.05f, false}, "motion"));
    entries.push_back(
        makeEntry("appearance", "effects", tr("settings.schema.shared.shadow-blur.label"),
                  tr("settings.schema.appearance.global-shadow-blur.description"), {"shell", "shadow", "blur"},
                  SliderSetting{static_cast<float>(cfg.shell.shadow.blur), 0.0f, 100.0f, 1.0f, true}, "shadow depth"));
    entries.push_back(makeEntry(
        "appearance", "effects", tr("settings.schema.shared.shadow-x.label"),
        tr("settings.schema.appearance.global-shadow-x.description"), {"shell", "shadow", "offset_x"},
        SliderSetting{static_cast<float>(cfg.shell.shadow.offsetX), -40.0f, 40.0f, 1.0f, true}, "shadow offset", true));
    entries.push_back(makeEntry(
        "appearance", "effects", tr("settings.schema.shared.shadow-y.label"),
        tr("settings.schema.appearance.global-shadow-y.description"), {"shell", "shadow", "offset_y"},
        SliderSetting{static_cast<float>(cfg.shell.shadow.offsetY), -40.0f, 40.0f, 1.0f, true}, "shadow offset", true));
    entries.push_back(
        makeEntry("appearance", "effects", tr("settings.schema.shared.shadow-alpha.label"),
                  tr("settings.schema.appearance.global-shadow-alpha.description"), {"shell", "shadow", "alpha"},
                  SliderSetting{cfg.shell.shadow.alpha, 0.0f, 1.0f, 0.01f, false}, "shadow opacity", true));

    // Wallpaper
    entries.push_back(makeEntry("wallpaper", "general", tr("settings.schema.shared.enabled.label"),
                                tr("settings.schema.wallpaper.enabled.description"), {"wallpaper", "enabled"},
                                ToggleSetting{cfg.wallpaper.enabled}, "background image"));
    entries.push_back(makeEntry("wallpaper", "general", tr("settings.schema.wallpaper.fill-mode.label"),
                                tr("settings.schema.wallpaper.fill-mode.description"), {"wallpaper", "fill_mode"},
                                asSegmented(enumSelect(kWallpaperFillModes, cfg.wallpaper.fillMode)), "scale aspect"));
    {
      ColorSetting fillColor;
      fillColor.unset = !cfg.wallpaper.fillColor.has_value();
      if (!fillColor.unset) {
        fillColor.hex = formatRgbHex(resolveColorSpec(*cfg.wallpaper.fillColor));
      }
      entries.push_back(makeEntry("wallpaper", "general", tr("settings.schema.wallpaper.fill-color.label"),
                                  tr("settings.schema.wallpaper.fill-color.description"), {"wallpaper", "fill_color"},
                                  std::move(fillColor), "background solid color"));
    }
    entries.push_back(makeEntry("wallpaper", "directories", tr("settings.schema.wallpaper.directory.label"),
                                tr("settings.schema.wallpaper.directory.description"), {"wallpaper", "directory"},
                                TextSetting{cfg.wallpaper.directory, "~/Pictures/Wallpapers"}, "folder path"));
    entries.push_back(makeEntry(
        "wallpaper", "directories", tr("settings.schema.wallpaper.directory-light.label"),
        tr("settings.schema.wallpaper.directory-light.description"), {"wallpaper", "directory_light"},
        TextSetting{cfg.wallpaper.directoryLight, tr("settings.schema.wallpaper.directory-light.placeholder")},
        "folder path light theme", true));
    entries.push_back(
        makeEntry("wallpaper", "directories", tr("settings.schema.wallpaper.directory-dark.label"),
                  tr("settings.schema.wallpaper.directory-dark.description"), {"wallpaper", "directory_dark"},
                  TextSetting{cfg.wallpaper.directoryDark, tr("settings.schema.wallpaper.directory-dark.placeholder")},
                  "folder path dark theme", true));
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
      entries.push_back(makeEntry("wallpaper", "transition", tr("settings.schema.wallpaper.transitions.label"),
                                  tr("settings.schema.wallpaper.transitions.description"), {"wallpaper", "transition"},
                                  std::move(transitions), "effects animation pool"));
    }
    entries.push_back(
        makeEntry("wallpaper", "transition", tr("settings.schema.wallpaper.transition-duration.label"),
                  tr("settings.schema.wallpaper.transition-duration.description"), {"wallpaper", "transition_duration"},
                  SliderSetting{cfg.wallpaper.transitionDurationMs, 100.0f, 30000.0f, 100.0f, true}, "fade animation"));
    entries.push_back(makeEntry(
        "wallpaper", "transition", tr("settings.schema.wallpaper.edge-smoothness.label"),
        tr("settings.schema.wallpaper.edge-smoothness.description"), {"wallpaper", "edge_smoothness"},
        SliderSetting{cfg.wallpaper.edgeSmoothness, 0.0f, 1.0f, 0.01f, false}, "transition feathering", true));
    entries.push_back(makeEntry("wallpaper", "automation", tr("settings.schema.wallpaper.automation.label"),
                                tr("settings.schema.wallpaper.automation.description"),
                                {"wallpaper", "automation", "enabled"}, ToggleSetting{cfg.wallpaper.automation.enabled},
                                "rotate slideshow"));
    entries.push_back(makeEntry(
        "wallpaper", "automation", tr("settings.schema.wallpaper.automation-interval.label"),
        tr("settings.schema.wallpaper.automation-interval.description"),
        {"wallpaper", "automation", "interval_minutes"},
        SliderSetting{static_cast<float>(cfg.wallpaper.automation.intervalMinutes), 0.0f, 1440.0f, 1.0f, true},
        "rotate slideshow"));
    entries.push_back(makeEntry(
        "wallpaper", "automation", tr("settings.schema.wallpaper.automation-order.label"),
        tr("settings.schema.wallpaper.automation-order.description"), {"wallpaper", "automation", "order"},
        asSegmented(enumSelect(kWallpaperAutomationOrders, cfg.wallpaper.automation.order)), "rotate slideshow"));
    entries.push_back(makeEntry("wallpaper", "automation", tr("settings.schema.wallpaper.automation-recursive.label"),
                                tr("settings.schema.wallpaper.automation-recursive.description"),
                                {"wallpaper", "automation", "recursive"},
                                ToggleSetting{cfg.wallpaper.automation.recursive}, "subdirectories", true));

    // Backdrop (niri-only: surface tracks niri overview state)
    if (env.niriBackdropSupported) {
      entries.push_back(makeEntry("backdrop", "general", tr("settings.schema.shared.enabled.label"),
                                  tr("settings.schema.backdrop.enabled.description"), {"backdrop", "enabled"},
                                  ToggleSetting{cfg.backdrop.enabled}, "wallpaper backdrop"));
      entries.push_back(makeEntry("backdrop", "backdrop", tr("settings.schema.backdrop.blur-intensity.label"),
                                  tr("settings.schema.backdrop.blur-intensity.description"),
                                  {"backdrop", "blur_intensity"},
                                  SliderSetting{cfg.backdrop.blurIntensity, 0.0f, 1.0f, 0.01f, false}, "wallpaper"));
      entries.push_back(makeEntry("backdrop", "backdrop", tr("settings.schema.backdrop.tint-intensity.label"),
                                  tr("settings.schema.backdrop.tint-intensity.description"),
                                  {"backdrop", "tint_intensity"},
                                  SliderSetting{cfg.backdrop.tintIntensity, 0.0f, 1.0f, 0.01f, false}, "wallpaper"));
    }

    // Templates
    entries.push_back(makeEntry("templates", "built-in", tr("settings.schema.templates.enable-builtins.label"),
                                tr("settings.schema.templates.enable-builtins.description"),
                                {"theme", "templates", "enable_builtin_templates"},
                                ToggleSetting{cfg.theme.templates.enableBuiltinTemplates}, "theme templates"));
    {
      const auto availableTemplates = noctalia::theme::availableTemplates();
      std::vector<SelectOption> templateOptions;
      templateOptions.reserve(availableTemplates.size());
      for (const auto& t : availableTemplates) {
        templateOptions.push_back(SelectOption{t.id, t.displayName});
      }
      entries.push_back(makeEntry(
          "templates", "built-in", tr("settings.schema.templates.builtin-ids.label"),
          tr("settings.schema.templates.builtin-ids.description"), {"theme", "templates", "builtin_ids"},
          ListSetting{.items = cfg.theme.templates.builtinIds, .suggestedOptions = std::move(templateOptions)},
          "theme templates apps foot walker gtk"));
    }
    entries.push_back(
        makeEntry("templates", "community", tr("settings.schema.templates.enable-community-templates.label"),
                  tr("settings.schema.templates.enable-community-templates.description"),
                  {"theme", "templates", "enable_community_templates"},
                  ToggleSetting{cfg.theme.templates.enableCommunityTemplates}, "theme templates community"));
    entries.push_back(
        makeEntry("templates", "community", tr("settings.schema.templates.community-ids.label"),
                  tr("settings.schema.templates.community-ids.description"), {"theme", "templates", "community_ids"},
                  ListSetting{.items = cfg.theme.templates.communityIds, .suggestedOptions = env.communityTemplates},
                  "theme templates community apps discord fuzzel vscode walker"));
    entries.push_back(makeEntry("templates", "user", tr("settings.schema.templates.enable-user-templates.label"),
                                tr("settings.schema.templates.enable-user-templates.description"),
                                {"theme", "templates", "enable_user_templates"},
                                ToggleSetting{cfg.theme.templates.enableUserTemplates}, "theme templates user custom"));
    entries.push_back(makeEntry("templates", "user", tr("settings.schema.templates.user-config.label"),
                                tr("settings.schema.templates.user-config.description"),
                                {"theme", "templates", "user_config"},
                                TextSetting{cfg.theme.templates.userConfig, "~/.config/noctalia/user-templates.toml"},
                                "theme templates path file", true));

    // Dock
    entries.push_back(makeEntry("dock", "general", tr("settings.schema.shared.enabled.label"),
                                tr("settings.schema.dock.enabled.description"), {"dock", "enabled"},
                                ToggleSetting{cfg.dock.enabled}, "launcher apps"));
    entries.push_back(makeEntry("dock", "general", tr("settings.schema.dock.active-monitor-only.label"),
                                tr("settings.schema.dock.active-monitor-only.description"),
                                {"dock", "active_monitor_only"}, ToggleSetting{cfg.dock.activeMonitorOnly}, "monitor"));
    entries.push_back(makeEntry("dock", "behavior", tr("settings.schema.shared.auto-hide.label"),
                                tr("settings.schema.dock.auto-hide.description"), {"dock", "auto_hide"},
                                ToggleSetting{cfg.dock.autoHide}, "autohide"));
    if (cfg.dock.autoHide)
      entries.push_back(makeEntry("dock", "behavior", tr("settings.schema.shared.reserve-space.label"),
                                  tr("settings.schema.dock.reserve-space.description"), {"dock", "reserve_space"},
                                  ToggleSetting{cfg.dock.reserveSpace}, "exclusive zone"));
    entries.push_back(makeEntry("dock", "behavior", tr("settings.schema.dock.show-running.label"),
                                tr("settings.schema.dock.show-running.description"), {"dock", "show_running"},
                                ToggleSetting{cfg.dock.showRunning}, "windows"));
    entries.push_back(makeEntry("dock", "behavior", tr("settings.schema.dock.show-instance-count.label"),
                                tr("settings.schema.dock.show-instance-count.description"),
                                {"dock", "show_instance_count"}, ToggleSetting{cfg.dock.showInstanceCount},
                                "badge windows"));
    entries.push_back(makeEntry("dock", "layout", tr("settings.schema.shared.position.label"),
                                tr("settings.schema.dock.position.description"), {"dock", "position"},
                                positionSelect(cfg.dock.position), "edge"));
    entries.push_back(makeEntry("dock", "layout", tr("settings.schema.dock.icon-size.label"),
                                tr("settings.schema.dock.icon-size.description"), {"dock", "icon_size"},
                                SliderSetting{static_cast<float>(cfg.dock.iconSize), 16.0f, 128.0f, 1.0f, true},
                                "apps"));
    entries.push_back(makeEntry(
        "dock", "layout", tr("settings.schema.shared.padding.label"), tr("settings.schema.dock.padding.description"),
        {"dock", "padding"}, SliderSetting{static_cast<float>(cfg.dock.padding), 0.0f, 100.0f, 1.0f, true}, "inset"));
    entries.push_back(makeEntry("dock", "layout", tr("settings.schema.dock.item-spacing.label"),
                                tr("settings.schema.dock.item-spacing.description"), {"dock", "item_spacing"},
                                SliderSetting{static_cast<float>(cfg.dock.itemSpacing), 0.0f, 100.0f, 1.0f, true},
                                "gap"));
    entries.push_back(makeEntry("dock", "layout", tr("settings.schema.shared.horizontal-margin.label"),
                                tr("settings.schema.dock.horizontal-margin.description"), {"dock", "margin_h"},
                                SliderSetting{static_cast<float>(cfg.dock.marginH), 0.0f, 500.0f, 1.0f, true},
                                "gap inset"));
    entries.push_back(makeEntry("dock", "layout", tr("settings.schema.shared.vertical-margin.label"),
                                tr("settings.schema.dock.vertical-margin.description"), {"dock", "margin_v"},
                                SliderSetting{static_cast<float>(cfg.dock.marginV), 0.0f, 100.0f, 1.0f, true},
                                "gap inset"));
    entries.push_back(makeEntry("dock", "shape", tr("settings.schema.shared.corner-radius.label"),
                                tr("settings.schema.dock.corner-radius.description"), {"dock", "radius"},
                                SliderSetting{static_cast<float>(cfg.dock.radius), 0.0f, 80.0f, 1.0f, true},
                                "rounded"));
    entries.push_back(makeEntry("dock", "shape", tr("settings.schema.shared.background-opacity.label"),
                                tr("settings.schema.dock.background-opacity.description"),
                                {"dock", "background_opacity"},
                                SliderSetting{cfg.dock.backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "alpha"));
    entries.push_back(makeEntry("dock", "effects", tr("settings.schema.shared.shadow.label"),
                                tr("settings.schema.dock.shadow.description"), {"dock", "shadow"},
                                ToggleSetting{cfg.dock.shadow}, "shadow"));
    entries.push_back(makeEntry("dock", "focus-styling", tr("settings.schema.dock.active-icon-scale.label"),
                                tr("settings.schema.dock.active-icon-scale.description"), {"dock", "active_scale"},
                                SliderSetting{cfg.dock.activeScale, 0.1f, 1.75f, 0.05f, false}, "focused", true));
    entries.push_back(makeEntry("dock", "focus-styling", tr("settings.schema.dock.inactive-icon-scale.label"),
                                tr("settings.schema.dock.inactive-icon-scale.description"), {"dock", "inactive_scale"},
                                SliderSetting{cfg.dock.inactiveScale, 0.1f, 1.0f, 0.05f, false}, "unfocused", true));
    entries.push_back(makeEntry("dock", "focus-styling", tr("settings.schema.dock.active-icon-opacity.label"),
                                tr("settings.schema.dock.active-icon-opacity.description"), {"dock", "active_opacity"},
                                SliderSetting{cfg.dock.activeOpacity, 0.0f, 1.0f, 0.01f, false}, "focused alpha",
                                true));
    entries.push_back(
        makeEntry("dock", "focus-styling", tr("settings.schema.dock.inactive-icon-opacity.label"),
                  tr("settings.schema.dock.inactive-icon-opacity.description"), {"dock", "inactive_opacity"},
                  SliderSetting{cfg.dock.inactiveOpacity, 0.0f, 1.0f, 0.01f, false}, "unfocused alpha", true));
    entries.push_back(makeEntry("dock", "pinned-apps", tr("settings.schema.dock.pinned-apps.label"),
                                tr("settings.schema.dock.pinned-apps.description"), {"dock", "pinned"},
                                ListSetting{.items = cfg.dock.pinned}, "favorites"));

    // Desktop
    entries.push_back(makeEntry("desktop", "widgets", tr("settings.schema.desktop.widgets.label"),
                                tr("settings.schema.desktop.widgets.description"), {"desktop_widgets", "enabled"},
                                ToggleSetting{cfg.desktopWidgets.enabled}, "desktop"));
    entries.push_back(makeEntry("desktop", "screen-corners", tr("settings.schema.desktop.screen-corners-enabled.label"),
                                tr("settings.schema.desktop.screen-corners-enabled.description"),
                                {"shell", "screen_corners", "enabled"}, ToggleSetting{cfg.shell.screenCorners.enabled},
                                "screen corners rounded"));
    entries.push_back(
        makeEntry("desktop", "screen-corners", tr("settings.schema.desktop.screen-corners-size.label"),
                  tr("settings.schema.desktop.screen-corners-size.description"), {"shell", "screen_corners", "size"},
                  SliderSetting{static_cast<float>(cfg.shell.screenCorners.size), 1.0f, 100.0f, 1.0f, true},
                  "screen corners radius"));

    // Shell
    entries.push_back(makeEntry("shell", "profile", tr("settings.schema.shell.avatar-path.label"),
                                tr("settings.schema.shell.avatar-path.description"), {"shell", "avatar_path"},
                                TextSetting{cfg.shell.avatarPath, tr("settings.schema.shell.avatar-path.placeholder")},
                                "image picture"));
    entries.push_back(makeEntry("shell", "network", tr("settings.schema.shell.offline-mode.label"),
                                tr("settings.schema.shell.offline-mode.description"), {"shell", "offline_mode"},
                                ToggleSetting{cfg.shell.offlineMode}, "network http fetch download"));
    entries.push_back(makeEntry("shell", "network", tr("settings.schema.shell.telemetry.label"),
                                tr("settings.schema.shell.telemetry.description"), {"shell", "telemetry_enabled"},
                                ToggleSetting{cfg.shell.telemetryEnabled}, "analytics ping privacy"));
    entries.push_back(makeEntry("shell", "security", tr("settings.schema.shell.polkit-agent.label"),
                                tr("settings.schema.shell.polkit-agent.description"), {"shell", "polkit_agent"},
                                ToggleSetting{cfg.shell.polkitAgent}, "auth password"));
    entries.push_back(makeEntry("shell", "security", tr("settings.schema.shell.password-style.label"),
                                tr("settings.schema.shell.password-style.description"), {"shell", "password_style"},
                                asSegmented(enumSelect(kPasswordMaskStyles, cfg.shell.passwordMaskStyle)),
                                "polkit lock mask"));
    entries.push_back(makeEntry("shell", "location", tr("settings.schema.shell.show-location.label"),
                                tr("settings.schema.shell.show-location.description"), {"shell", "show_location"},
                                ToggleSetting{cfg.shell.showLocation}, "weather"));
    entries.push_back(makeEntry("shell", "clipboard", tr("settings.schema.shell.clipboard-auto-paste.label"),
                                tr("settings.schema.shell.clipboard-auto-paste.description"),
                                {"shell", "clipboard_auto_paste"},
                                enumSelect(kClipboardAutoPasteModes, cfg.shell.clipboardAutoPaste), "clipboard paste"));
    entries.push_back(makeEntry("shell", "osd", tr("settings.schema.shell.osd-position.label"),
                                tr("settings.schema.shell.osd-position.description"), {"osd", "position"},
                                plainSelect({{"top_right", "settings.options.screen-position.top-right"},
                                             {"top_left", "settings.options.screen-position.top-left"},
                                             {"top_center", "settings.options.screen-position.top-center"},
                                             {"bottom_right", "settings.options.screen-position.bottom-right"},
                                             {"bottom_left", "settings.options.screen-position.bottom-left"},
                                             {"bottom_center", "settings.options.screen-position.bottom-center"}},
                                            cfg.osd.position),
                                "hud overlay volume brightness"));

    // Services
    entries.push_back(makeEntry("services", "system", tr("settings.schema.services.system-monitor.label"),
                                tr("settings.schema.services.system-monitor.description"),
                                {"system", "monitor", "enabled"}, ToggleSetting{cfg.system.monitor.enabled},
                                "system monitor cpu ram memory"));
    entries.push_back(makeEntry("services", "weather", tr("settings.schema.services.weather.label"),
                                tr("settings.schema.services.weather.description"), {"weather", "enabled"},
                                ToggleSetting{cfg.weather.enabled}, "forecast"));
    entries.push_back(makeEntry("services", "weather", tr("settings.schema.services.weather-location.label"),
                                tr("settings.schema.services.weather-location.description"), {"weather", "auto_locate"},
                                ToggleSetting{cfg.weather.autoLocate}, "forecast gps"));
    entries.push_back(makeEntry("services", "weather", tr("settings.schema.services.weather-unit.label"),
                                tr("settings.schema.services.weather-unit.description"), {"weather", "unit"},
                                asSegmented(plainSelect({{"celsius", "settings.options.weather.unit.celsius"},
                                                         {"fahrenheit", "settings.options.weather.unit.fahrenheit"}},
                                                        cfg.weather.unit)),
                                "temperature"));
    entries.push_back(makeEntry(
        "services", "weather", tr("settings.schema.services.weather-address.label"),
        tr("settings.schema.services.weather-address.description"), {"weather", "address"},
        TextSetting{cfg.weather.address, tr("settings.schema.services.weather-address.placeholder")}, "location"));
    entries.push_back(makeEntry("services", "weather", tr("settings.schema.services.weather-effects.label"),
                                tr("settings.schema.services.weather-effects.description"), {"weather", "effects"},
                                ToggleSetting{cfg.weather.effects}, "forecast visuals"));
    entries.push_back(
        makeEntry("services", "weather", tr("settings.schema.services.weather-refresh-interval.label"),
                  tr("settings.schema.services.weather-refresh-interval.description"), {"weather", "refresh_minutes"},
                  SliderSetting{static_cast<float>(cfg.weather.refreshMinutes), 5.0f, 240.0f, 5.0f, true}, "forecast"));
    entries.push_back(makeEntry("services", "audio", tr("settings.schema.services.audio-overdrive.label"),
                                tr("settings.schema.services.audio-overdrive.description"),
                                {"audio", "enable_overdrive"}, ToggleSetting{cfg.audio.enableOverdrive}, "volume"));
    entries.push_back(makeEntry("services", "audio", tr("settings.schema.services.shell-sounds.label"),
                                tr("settings.schema.services.shell-sounds.description"), {"audio", "enable_sounds"},
                                ToggleSetting{cfg.audio.enableSounds}, "sound"));
    entries.push_back(makeEntry("services", "audio", tr("settings.schema.services.sound-volume.label"),
                                tr("settings.schema.services.sound-volume.description"), {"audio", "sound_volume"},
                                SliderSetting{cfg.audio.soundVolume, 0.0f, 1.0f, 0.01f, false}, "sound"));
    entries.push_back(makeEntry(
        "services", "audio", tr("settings.schema.services.volume-change-sound.label"),
        tr("settings.schema.services.volume-change-sound.description"), {"audio", "volume_change_sound"},
        TextSetting{cfg.audio.volumeChangeSound, tr("settings.schema.services.volume-change-sound.placeholder")},
        "sound path file", true));
    entries.push_back(makeEntry(
        "services", "audio", tr("settings.schema.services.notification-sound.label"),
        tr("settings.schema.services.notification-sound.description"), {"audio", "notification_sound"},
        TextSetting{cfg.audio.notificationSound, tr("settings.schema.services.notification-sound.placeholder")},
        "sound path file", true));
    entries.push_back(makeEntry("services", "media", tr("settings.schema.services.mpris-blacklist.label"),
                                tr("settings.schema.services.mpris-blacklist.description"),
                                {"shell", "mpris", "blacklist"}, ListSetting{.items = cfg.shell.mpris.blacklist},
                                "mpris media player dbus session blacklist"));
    entries.push_back(makeEntry("services", "brightness", tr("settings.schema.services.ddcutil.label"),
                                tr("settings.schema.services.ddcutil.description"), {"brightness", "enable_ddcutil"},
                                ToggleSetting{cfg.brightness.enableDdcutil}, "monitor ddcutil"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.schema.services.night-light.label"),
                                tr("settings.schema.services.night-light.description"), {"nightlight", "enabled"},
                                ToggleSetting{cfg.nightlight.enabled}, "wlsunset"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.schema.services.force-night-light.label"),
                                tr("settings.schema.services.force-night-light.description"), {"nightlight", "force"},
                                ToggleSetting{cfg.nightlight.force}, "wlsunset"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.schema.services.use-weather-location.label"),
                                tr("settings.schema.services.use-weather-location.description"),
                                {"nightlight", "use_weather_location"},
                                ToggleSetting{cfg.nightlight.useWeatherLocation}, "location"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.schema.services.night-light-start-time.label"),
                                tr("settings.schema.services.night-light-start-time.description"),
                                {"nightlight", "start_time"}, TextSetting{cfg.nightlight.startTime, "20:30"},
                                "time schedule sunset"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.schema.services.night-light-stop-time.label"),
                                tr("settings.schema.services.night-light-stop-time.description"),
                                {"nightlight", "stop_time"}, TextSetting{cfg.nightlight.stopTime, "07:30"},
                                "time schedule sunrise"));
    entries.push_back(makeEntry("services", "night-light", tr("settings.schema.services.latitude.label"),
                                tr("settings.schema.services.latitude.description"), {"nightlight", "latitude"},
                                OptionalNumberSetting{cfg.nightlight.latitude, -90.0, 90.0, "52.5200"},
                                "coordinate location sunrise sunset", true));
    entries.push_back(makeEntry("services", "night-light", tr("settings.schema.services.longitude.label"),
                                tr("settings.schema.services.longitude.description"), {"nightlight", "longitude"},
                                OptionalNumberSetting{cfg.nightlight.longitude, -180.0, 180.0, "13.4050"},
                                "coordinate location sunrise sunset", true));
    entries.push_back(
        makeEntry("services", "night-light", tr("settings.schema.services.day-temperature.label"),
                  tr("settings.schema.services.day-temperature.description"), {"nightlight", "temperature_day"},
                  SliderSetting{static_cast<float>(cfg.nightlight.dayTemperature), 1000.0f, 10000.0f, 100.0f, true},
                  "wlsunset kelvin"));
    entries.push_back(
        makeEntry("services", "night-light", tr("settings.schema.services.night-temperature.label"),
                  tr("settings.schema.services.night-temperature.description"), {"nightlight", "temperature_night"},
                  SliderSetting{static_cast<float>(cfg.nightlight.nightTemperature), 1000.0f, 10000.0f, 100.0f, true},
                  "wlsunset kelvin"));

    // Notifications
    entries.push_back(makeEntry("notifications", "general", tr("settings.schema.notifications.daemon.label"),
                                tr("settings.schema.notifications.daemon.description"),
                                {"notification", "enable_daemon"}, ToggleSetting{cfg.notification.enableDaemon},
                                "dbus"));
    entries.push_back(makeEntry("notifications", "toasts", tr("settings.schema.notifications.position.label"),
                                tr("settings.schema.notifications.position.description"), {"notification", "position"},
                                plainSelect({{"top_right", "settings.options.screen-position.top-right"},
                                             {"top_left", "settings.options.screen-position.top-left"},
                                             {"top_center", "settings.options.screen-position.top-center"},
                                             {"bottom_right", "settings.options.screen-position.bottom-right"},
                                             {"bottom_left", "settings.options.screen-position.bottom-left"},
                                             {"bottom_center", "settings.options.screen-position.bottom-center"}},
                                            cfg.notification.position),
                                "toast popup placement anchor"));
    entries.push_back(makeEntry(
        "notifications", "toasts", tr("settings.schema.notifications.layer.label"),
        tr("settings.schema.notifications.layer.description"), {"notification", "layer"},
        asSegmented(plainSelect({{"top", "settings.options.layer.top"}, {"overlay", "settings.options.layer.overlay"}},
                                cfg.notification.layer)),
        "toast layer shell z-order"));
    entries.push_back(makeEntry("notifications", "toasts", tr("settings.schema.notifications.toast-opacity.label"),
                                tr("settings.schema.notifications.toast-opacity.description"),
                                {"notification", "background_opacity"},
                                SliderSetting{cfg.notification.backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "popup"));
    entries.push_back(
        makeEntry("notifications", "toasts", tr("settings.schema.notifications.monitors.label"),
                  tr("settings.schema.notifications.monitors.description"), {"notification", "monitors"},
                  ListSetting{.items = cfg.notification.monitors, .suggestedOptions = env.availableOutputs},
                  "monitor output display screen"));

    // Bar
    if (selectedBar != nullptr && selectedMonitorOverride == nullptr) {
      const std::string section = "bar";
      const std::vector<std::string> root = {"bar", selectedBar->name};
      auto path = [&](std::string key) {
        std::vector<std::string> p = root;
        p.push_back(std::move(key));
        return p;
      };
      entries.push_back(makeEntry(section, "general", tr("settings.schema.shared.enabled.label"),
                                  tr("settings.schema.bar.enabled.description"), path("enabled"),
                                  ToggleSetting{selectedBar->enabled}, "visible"));
      entries.push_back(makeEntry(section, "general", tr("settings.schema.shared.position.label"),
                                  tr("settings.schema.bar.position.description"), path("position"),
                                  positionSelect(selectedBar->position), "edge"));
      entries.push_back(makeEntry(section, "general", tr("settings.schema.shared.auto-hide.label"),
                                  tr("settings.schema.bar.auto-hide.description"), path("auto_hide"),
                                  ToggleSetting{selectedBar->autoHide}, "autohide"));
      entries.push_back(makeEntry(section, "general", tr("settings.schema.shared.reserve-space.label"),
                                  tr("settings.schema.bar.reserve-space.description"), path("reserve_space"),
                                  ToggleSetting{selectedBar->reserveSpace}, "exclusive zone"));
      entries.push_back(makeEntry(section, "general", tr("settings.schema.bar.attach-panels.label"),
                                  tr("settings.schema.bar.attach-panels.description"), path("attach_panels"),
                                  ToggleSetting{selectedBar->attachPanels}, "panel popup attach float"));
      entries.push_back(makeEntry(section, "layout", tr("settings.schema.bar.thickness.label"),
                                  tr("settings.schema.bar.thickness.description"), path("thickness"),
                                  SliderSetting{static_cast<float>(selectedBar->thickness), 10.0f, 120.0f, 1.0f, true},
                                  "height width"));
      entries.push_back(makeEntry(section, "layout", tr("settings.schema.bar.content-scale.label"),
                                  tr("settings.schema.bar.content-scale.description"), path("scale"),
                                  SliderSetting{selectedBar->scale, 0.5f, 4.0f, 0.05f, false}, "zoom size"));
      entries.push_back(makeEntry(section, "layout", tr("settings.schema.shared.horizontal-margin.label"),
                                  tr("settings.schema.bar.horizontal-margin.description"), path("margin_h"),
                                  SliderSetting{static_cast<float>(selectedBar->marginH), 0.0f, 500.0f, 1.0f, true},
                                  "gap inset"));
      entries.push_back(makeEntry(section, "layout", tr("settings.schema.shared.vertical-margin.label"),
                                  tr("settings.schema.bar.vertical-margin.description"), path("margin_v"),
                                  SliderSetting{static_cast<float>(selectedBar->marginV), 0.0f, 100.0f, 1.0f, true},
                                  "gap inset"));
      entries.push_back(makeEntry(section, "layout", tr("settings.schema.bar.content-padding.label"),
                                  tr("settings.schema.bar.content-padding.description"), path("padding"),
                                  SliderSetting{static_cast<float>(selectedBar->padding), 0.0f, 80.0f, 1.0f, true},
                                  "inset"));
      entries.push_back(makeEntry(section, "shape", tr("settings.schema.shared.corner-radius.label"),
                                  tr("settings.schema.bar.corner-radius.description"), path("radius"),
                                  SliderSetting{static_cast<float>(selectedBar->radius), 0.0f, 80.0f, 1.0f, true},
                                  "rounded"));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.schema.bar.corner-top-left.label"),
                    tr("settings.schema.bar.corner-top-left.description"), path("radius_top_left"),
                    SliderSetting{static_cast<float>(selectedBar->radiusTopLeft), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.schema.bar.corner-top-right.label"),
                    tr("settings.schema.bar.corner-top-right.description"), path("radius_top_right"),
                    SliderSetting{static_cast<float>(selectedBar->radiusTopRight), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.schema.bar.corner-bottom-left.label"),
                    tr("settings.schema.bar.corner-bottom-left.description"), path("radius_bottom_left"),
                    SliderSetting{static_cast<float>(selectedBar->radiusBottomLeft), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.schema.bar.corner-bottom-right.label"),
                    tr("settings.schema.bar.corner-bottom-right.description"), path("radius_bottom_right"),
                    SliderSetting{static_cast<float>(selectedBar->radiusBottomRight), 0.0f, 80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(makeEntry(section, "shape", tr("settings.schema.shared.background-opacity.label"),
                                  tr("settings.schema.bar.background-opacity.description"), path("background_opacity"),
                                  SliderSetting{selectedBar->backgroundOpacity, 0.0f, 1.0f, 0.01f, false}, "alpha"));
      entries.push_back(makeEntry(section, "effects", tr("settings.schema.shared.shadow.label"),
                                  tr("settings.schema.bar.shadow.description"), path("shadow"),
                                  ToggleSetting{selectedBar->shadow}, "shadow"));
      entries.push_back(makeEntry(section, "effects", tr("settings.schema.shared.contact-shadow.label"),
                                  tr("settings.schema.bar.contact-shadow.description"), path("contact_shadow"),
                                  ToggleSetting{selectedBar->contactShadow}, "shadow contact panel attached"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.widget-capsules.label"),
                                  tr("settings.schema.bar.widget-capsules.description"), path("capsule"),
                                  ToggleSetting{selectedBar->widgetCapsuleDefault}, "pill"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.widget-color.label"),
                                  tr("settings.schema.bar.widget-color.description"), path("color"),
                                  optionalColorRolePicker(selectedBar->widgetColor), "color role foreground", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.capsule-fill.label"),
                                  tr("settings.schema.bar.capsule-fill.description"), path("capsule_fill"),
                                  colorRolePicker(selectedBar->widgetCapsuleFill), "color role pill", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.capsule-foreground.label"),
                                  tr("settings.schema.bar.capsule-foreground.description"), path("capsule_foreground"),
                                  optionalColorRolePicker(selectedBar->widgetCapsuleForeground),
                                  "color role foreground pill", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.capsule-border.label"),
                                  tr("settings.schema.bar.capsule-border.description"), path("capsule_border"),
                                  capsuleBorderRolePicker(selectedBar->widgetCapsuleBorder), "color role pill outline",
                                  true));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.schema.bar.widget-spacing.label"),
                    tr("settings.schema.bar.widget-spacing.description"), path("widget_spacing"),
                    SliderSetting{static_cast<float>(selectedBar->widgetSpacing), 0.0f, 32.0f, 1.0f, true}, "gap"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.capsule-padding.label"),
                                  tr("settings.schema.bar.capsule-padding.description"), path("capsule_padding"),
                                  SliderSetting{selectedBar->widgetCapsulePadding, 0.0f, 48.0f, 1.0f, false},
                                  "pill inset", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.capsule-opacity.label"),
                                  tr("settings.schema.bar.capsule-opacity.description"), path("capsule_opacity"),
                                  SliderSetting{selectedBar->widgetCapsuleOpacity, 0.0f, 1.0f, 0.01f, false},
                                  "pill alpha", true));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.schema.bar.start-widgets.label"),
                                  tr("settings.schema.bar.start-widgets.description"), path("start"),
                                  ListSetting{.items = selectedBar->startWidgets}, "left"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.schema.bar.center-widgets.label"),
                                  tr("settings.schema.bar.center-widgets.description"), path("center"),
                                  ListSetting{.items = selectedBar->centerWidgets}, "middle"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.schema.bar.end-widgets.label"),
                                  tr("settings.schema.bar.end-widgets.description"), path("end"),
                                  ListSetting{.items = selectedBar->endWidgets}, "right"));
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

      entries.push_back(makeEntry(section, "general", tr("settings.schema.shared.enabled.label"),
                                  tr("settings.schema.bar.enabled.description"), mpath("enabled"),
                                  ToggleSetting{ovr.enabled.value_or(bar.enabled)}, "visible"));
      entries.push_back(makeEntry(section, "general", tr("settings.schema.shared.auto-hide.label"),
                                  tr("settings.schema.bar.auto-hide.description"), mpath("auto_hide"),
                                  ToggleSetting{ovr.autoHide.value_or(bar.autoHide)}, "autohide"));
      entries.push_back(makeEntry(section, "general", tr("settings.schema.shared.reserve-space.label"),
                                  tr("settings.schema.bar.reserve-space.description"), mpath("reserve_space"),
                                  ToggleSetting{ovr.reserveSpace.value_or(bar.reserveSpace)}, "exclusive zone"));
      entries.push_back(makeEntry(section, "general", tr("settings.schema.bar.attach-panels.label"),
                                  tr("settings.schema.bar.attach-panels.description"), mpath("attach_panels"),
                                  ToggleSetting{ovr.attachPanels.value_or(bar.attachPanels)},
                                  "panel popup attach float"));
      entries.push_back(
          makeEntry(section, "layout", tr("settings.schema.bar.thickness.label"),
                    tr("settings.schema.bar.thickness.description"), mpath("thickness"),
                    SliderSetting{static_cast<float>(ovr.thickness.value_or(bar.thickness)), 10.0f, 120.0f, 1.0f, true},
                    "height width"));
      entries.push_back(makeEntry(section, "layout", tr("settings.schema.bar.content-scale.label"),
                                  tr("settings.schema.bar.content-scale.description"), mpath("scale"),
                                  SliderSetting{ovr.scale.value_or(bar.scale), 0.5f, 4.0f, 0.05f, false}, "zoom size"));
      entries.push_back(makeEntry(
          section, "layout", tr("settings.schema.shared.horizontal-margin.label"),
          tr("settings.schema.bar.horizontal-margin.description"), mpath("margin_h"),
          SliderSetting{static_cast<float>(ovr.marginH.value_or(bar.marginH)), 0.0f, 500.0f, 1.0f, true}, "gap inset"));
      entries.push_back(makeEntry(
          section, "layout", tr("settings.schema.shared.vertical-margin.label"),
          tr("settings.schema.bar.vertical-margin.description"), mpath("margin_v"),
          SliderSetting{static_cast<float>(ovr.marginV.value_or(bar.marginV)), 0.0f, 100.0f, 1.0f, true}, "gap inset"));
      entries.push_back(makeEntry(
          section, "layout", tr("settings.schema.bar.content-padding.label"),
          tr("settings.schema.bar.content-padding.description"), mpath("padding"),
          SliderSetting{static_cast<float>(ovr.padding.value_or(bar.padding)), 0.0f, 80.0f, 1.0f, true}, "inset"));
      entries.push_back(makeEntry(
          section, "shape", tr("settings.schema.shared.corner-radius.label"),
          tr("settings.schema.bar.corner-radius.description"), mpath("radius"),
          SliderSetting{static_cast<float>(ovr.radius.value_or(bar.radius)), 0.0f, 80.0f, 1.0f, true}, "rounded"));
      entries.push_back(makeEntry(
          section, "shape", tr("settings.schema.bar.corner-top-left.label"),
          tr("settings.schema.bar.corner-top-left.description"), mpath("radius_top_left"),
          SliderSetting{static_cast<float>(ovr.radiusTopLeft.value_or(bar.radiusTopLeft)), 0.0f, 80.0f, 1.0f, true},
          "rounded corner", true));
      entries.push_back(makeEntry(
          section, "shape", tr("settings.schema.bar.corner-top-right.label"),
          tr("settings.schema.bar.corner-top-right.description"), mpath("radius_top_right"),
          SliderSetting{static_cast<float>(ovr.radiusTopRight.value_or(bar.radiusTopRight)), 0.0f, 80.0f, 1.0f, true},
          "rounded corner", true));
      entries.push_back(makeEntry(section, "shape", tr("settings.schema.bar.corner-bottom-left.label"),
                                  tr("settings.schema.bar.corner-bottom-left.description"), mpath("radius_bottom_left"),
                                  SliderSetting{static_cast<float>(ovr.radiusBottomLeft.value_or(bar.radiusBottomLeft)),
                                                0.0f, 80.0f, 1.0f, true},
                                  "rounded corner", true));
      entries.push_back(
          makeEntry(section, "shape", tr("settings.schema.bar.corner-bottom-right.label"),
                    tr("settings.schema.bar.corner-bottom-right.description"), mpath("radius_bottom_right"),
                    SliderSetting{static_cast<float>(ovr.radiusBottomRight.value_or(bar.radiusBottomRight)), 0.0f,
                                  80.0f, 1.0f, true},
                    "rounded corner", true));
      entries.push_back(makeEntry(
          section, "shape", tr("settings.schema.shared.background-opacity.label"),
          tr("settings.schema.bar.background-opacity.description"), mpath("background_opacity"),
          SliderSetting{ovr.backgroundOpacity.value_or(bar.backgroundOpacity), 0.0f, 1.0f, 0.01f, false}, "alpha"));
      entries.push_back(makeEntry(section, "effects", tr("settings.schema.shared.shadow.label"),
                                  tr("settings.schema.bar.shadow.description"), mpath("shadow"),
                                  ToggleSetting{ovr.shadow.value_or(bar.shadow)}, "shadow"));
      entries.push_back(makeEntry(section, "effects", tr("settings.schema.shared.contact-shadow.label"),
                                  tr("settings.schema.bar.contact-shadow.description"), mpath("contact_shadow"),
                                  ToggleSetting{ovr.contactShadow.value_or(bar.contactShadow)},
                                  "shadow contact panel attached"));
      entries.push_back(makeEntry(
          section, "widgets", tr("settings.schema.bar.widget-spacing.label"),
          tr("settings.schema.bar.widget-spacing.description"), mpath("widget_spacing"),
          SliderSetting{static_cast<float>(ovr.widgetSpacing.value_or(bar.widgetSpacing)), 0.0f, 32.0f, 1.0f, true},
          "gap"));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.widget-capsules.label"),
                                  tr("settings.schema.bar.widget-capsules.description"), mpath("capsule"),
                                  ToggleSetting{ovr.widgetCapsuleDefault.value_or(bar.widgetCapsuleDefault)}, "pill"));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.schema.bar.widget-color.label"),
                    tr("settings.schema.bar.widget-color.description"), mpath("color"),
                    optionalColorRolePicker(ovr.widgetColor.has_value() ? ovr.widgetColor : bar.widgetColor),
                    "color role foreground", true));
      entries.push_back(makeEntry(section, "widgets", tr("settings.schema.bar.capsule-fill.label"),
                                  tr("settings.schema.bar.capsule-fill.description"), mpath("capsule_fill"),
                                  colorRolePicker(ovr.widgetCapsuleFill.value_or(bar.widgetCapsuleFill)),
                                  "color role pill", true));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.schema.bar.capsule-foreground.label"),
                    tr("settings.schema.bar.capsule-foreground.description"), mpath("capsule_foreground"),
                    optionalColorRolePicker(ovr.widgetCapsuleForeground.has_value() ? ovr.widgetCapsuleForeground
                                                                                    : bar.widgetCapsuleForeground),
                    "color role foreground pill", true));
      entries.push_back(makeEntry(
          section, "widgets", tr("settings.schema.bar.capsule-border.label"),
          tr("settings.schema.bar.capsule-border.description"), mpath("capsule_border"),
          capsuleBorderRolePicker(ovr.widgetCapsuleBorderSpecified ? ovr.widgetCapsuleBorder : bar.widgetCapsuleBorder),
          "color role pill outline", true));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.schema.bar.capsule-padding.label"),
                    tr("settings.schema.bar.capsule-padding.description"), mpath("capsule_padding"),
                    SliderSetting{static_cast<float>(ovr.widgetCapsulePadding.value_or(bar.widgetCapsulePadding)), 0.0f,
                                  48.0f, 1.0f, false},
                    "pill inset", true));
      entries.push_back(
          makeEntry(section, "widgets", tr("settings.schema.bar.capsule-opacity.label"),
                    tr("settings.schema.bar.capsule-opacity.description"), mpath("capsule_opacity"),
                    SliderSetting{static_cast<float>(ovr.widgetCapsuleOpacity.value_or(bar.widgetCapsuleOpacity)), 0.0f,
                                  1.0f, 0.01f, false},
                    "pill alpha", true));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.schema.bar.start-widgets.label"),
                                  tr("settings.schema.bar.start-widgets.description"), mpath("start"),
                                  ListSetting{.items = ovr.startWidgets.value_or(bar.startWidgets)}, "left"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.schema.bar.center-widgets.label"),
                                  tr("settings.schema.bar.center-widgets.description"), mpath("center"),
                                  ListSetting{.items = ovr.centerWidgets.value_or(bar.centerWidgets)}, "middle"));
      entries.push_back(makeEntry(section, "widget-list", tr("settings.schema.bar.end-widgets.label"),
                                  tr("settings.schema.bar.end-widgets.description"), mpath("end"),
                                  ListSetting{.items = ovr.endWidgets.value_or(bar.endWidgets)}, "right"));
    }

    return entries;
  }

} // namespace settings
