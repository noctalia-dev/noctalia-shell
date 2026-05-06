#include "config/config_service.h"
#include "core/log.h"
#include "util/file_utils.h"

#include <algorithm>
#include <cmath>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <type_traits>
#include <vector>

namespace {
  constexpr Logger kLog("config");
  constexpr const char* kInternalStateTable = "noctalia_state";
  constexpr const char* kSetupWizardCompletedKey = "setup_wizard_completed";
  constexpr double kConfigFloatEpsilon = 1.0e-5;

  std::string overrideCacheKey(const std::vector<std::string>& path) {
    std::string key;
    for (const auto& part : path) {
      if (!key.empty()) {
        key.push_back('.');
      }
      key += part;
    }
    return key;
  }

  bool nearlyEqual(double a, double b) noexcept { return std::abs(a - b) <= kConfigFloatEpsilon; }

  bool colorEqual(const Color& a, const Color& b) noexcept {
    return nearlyEqual(a.r, b.r) && nearlyEqual(a.g, b.g) && nearlyEqual(a.b, b.b) && nearlyEqual(a.a, b.a);
  }

  bool colorSpecEqual(const ColorSpec& a, const ColorSpec& b) noexcept {
    return a.role == b.role && colorEqual(a.fixed, b.fixed) && nearlyEqual(a.alpha, b.alpha);
  }

  bool optionalDoubleEqual(const std::optional<double>& a, const std::optional<double>& b) noexcept {
    if (a.has_value() != b.has_value()) {
      return false;
    }
    return !a.has_value() || nearlyEqual(*a, *b);
  }

  bool optionalColorSpecEqual(const std::optional<ColorSpec>& a, const std::optional<ColorSpec>& b) noexcept {
    if (a.has_value() != b.has_value()) {
      return false;
    }
    return !a.has_value() || colorSpecEqual(*a, *b);
  }

  template <typename T, typename Equal>
  bool vectorEqual(const std::vector<T>& a, const std::vector<T>& b, Equal equal) {
    if (a.size() != b.size()) {
      return false;
    }
    for (std::size_t i = 0; i < a.size(); ++i) {
      if (!equal(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }

  std::optional<double> numericWidgetSetting(const WidgetSettingValue& value) {
    if (const auto* i = std::get_if<std::int64_t>(&value)) {
      return static_cast<double>(*i);
    }
    if (const auto* d = std::get_if<double>(&value)) {
      return *d;
    }
    return std::nullopt;
  }

  bool widgetSettingEqual(const WidgetSettingValue& a, const WidgetSettingValue& b) {
    const auto aNum = numericWidgetSetting(a);
    const auto bNum = numericWidgetSetting(b);
    if (aNum.has_value() || bNum.has_value()) {
      return aNum.has_value() && bNum.has_value() && nearlyEqual(*aNum, *bNum);
    }
    if (a.index() != b.index()) {
      return false;
    }
    return std::visit(
        [&](const auto& av) {
          using T = std::decay_t<decltype(av)>;
          const auto* bv = std::get_if<T>(&b);
          return bv != nullptr && av == *bv;
        },
        a);
  }

  bool widgetSettingsEqual(const std::unordered_map<std::string, WidgetSettingValue>& a,
                           const std::unordered_map<std::string, WidgetSettingValue>& b) {
    if (a.size() != b.size()) {
      return false;
    }
    for (const auto& [key, value] : a) {
      const auto it = b.find(key);
      if (it == b.end() || !widgetSettingEqual(value, it->second)) {
        return false;
      }
    }
    return true;
  }

  bool barBaseConfigEqual(const BarConfig& a, const BarConfig& b) {
    return a.name == b.name && a.position == b.position && a.enabled == b.enabled && a.autoHide == b.autoHide &&
           a.reserveSpace == b.reserveSpace && a.thickness == b.thickness &&
           nearlyEqual(a.backgroundOpacity, b.backgroundOpacity) && a.radius == b.radius &&
           a.radiusTopLeft == b.radiusTopLeft && a.radiusTopRight == b.radiusTopRight &&
           a.radiusBottomLeft == b.radiusBottomLeft && a.radiusBottomRight == b.radiusBottomRight &&
           a.marginEnds == b.marginEnds && a.marginEdge == b.marginEdge && a.padding == b.padding &&
           a.widgetSpacing == b.widgetSpacing && a.shadow == b.shadow && a.contactShadow == b.contactShadow &&
           a.attachPanels == b.attachPanels && nearlyEqual(a.scale, b.scale) && a.startWidgets == b.startWidgets &&
           a.centerWidgets == b.centerWidgets && a.endWidgets == b.endWidgets &&
           a.widgetCapsuleDefault == b.widgetCapsuleDefault &&
           colorSpecEqual(a.widgetCapsuleFill, b.widgetCapsuleFill) &&
           optionalColorSpecEqual(a.widgetCapsuleForeground, b.widgetCapsuleForeground) &&
           optionalColorSpecEqual(a.widgetColor, b.widgetColor) && a.widgetCapsuleGroups == b.widgetCapsuleGroups &&
           nearlyEqual(a.widgetCapsulePadding, b.widgetCapsulePadding) &&
           nearlyEqual(a.widgetCapsuleOpacity, b.widgetCapsuleOpacity) &&
           a.widgetCapsuleBorderSpecified == b.widgetCapsuleBorderSpecified &&
           optionalColorSpecEqual(a.widgetCapsuleBorder, b.widgetCapsuleBorder);
  }

  BarConfig applyMonitorOverrideForComparison(const BarConfig& base, const BarMonitorOverride& ovr) {
    BarConfig resolved = base;
    resolved.monitorOverrides.clear();
    if (ovr.enabled) {
      resolved.enabled = *ovr.enabled;
    }
    if (ovr.autoHide) {
      resolved.autoHide = *ovr.autoHide;
    }
    if (ovr.reserveSpace) {
      resolved.reserveSpace = *ovr.reserveSpace;
    }
    if (ovr.thickness) {
      resolved.thickness = *ovr.thickness;
    }
    if (ovr.backgroundOpacity) {
      resolved.backgroundOpacity = *ovr.backgroundOpacity;
    }
    if (ovr.radius) {
      resolved.radius = *ovr.radius;
      resolved.radiusTopLeft = *ovr.radius;
      resolved.radiusTopRight = *ovr.radius;
      resolved.radiusBottomLeft = *ovr.radius;
      resolved.radiusBottomRight = *ovr.radius;
    }
    if (ovr.radiusTopLeft) {
      resolved.radiusTopLeft = *ovr.radiusTopLeft;
    }
    if (ovr.radiusTopRight) {
      resolved.radiusTopRight = *ovr.radiusTopRight;
    }
    if (ovr.radiusBottomLeft) {
      resolved.radiusBottomLeft = *ovr.radiusBottomLeft;
    }
    if (ovr.radiusBottomRight) {
      resolved.radiusBottomRight = *ovr.radiusBottomRight;
    }
    if (ovr.marginEnds) {
      resolved.marginEnds = *ovr.marginEnds;
    }
    if (ovr.marginEdge) {
      resolved.marginEdge = *ovr.marginEdge;
    }
    if (ovr.padding) {
      resolved.padding = *ovr.padding;
    }
    if (ovr.widgetSpacing) {
      resolved.widgetSpacing = *ovr.widgetSpacing;
    }
    if (ovr.shadow) {
      resolved.shadow = *ovr.shadow;
    }
    if (ovr.contactShadow) {
      resolved.contactShadow = *ovr.contactShadow;
    }
    if (ovr.attachPanels) {
      resolved.attachPanels = *ovr.attachPanels;
    }
    if (ovr.startWidgets) {
      resolved.startWidgets = *ovr.startWidgets;
    }
    if (ovr.centerWidgets) {
      resolved.centerWidgets = *ovr.centerWidgets;
    }
    if (ovr.endWidgets) {
      resolved.endWidgets = *ovr.endWidgets;
    }
    if (ovr.scale) {
      resolved.scale = *ovr.scale;
    }
    if (ovr.widgetCapsuleDefault) {
      resolved.widgetCapsuleDefault = *ovr.widgetCapsuleDefault;
    }
    if (ovr.widgetCapsuleFill) {
      resolved.widgetCapsuleFill = *ovr.widgetCapsuleFill;
    }
    if (ovr.widgetCapsuleBorderSpecified) {
      resolved.widgetCapsuleBorderSpecified = true;
      resolved.widgetCapsuleBorder = ovr.widgetCapsuleBorder;
    }
    if (ovr.widgetCapsuleForeground) {
      resolved.widgetCapsuleForeground = *ovr.widgetCapsuleForeground;
    }
    if (ovr.widgetColor) {
      resolved.widgetColor = *ovr.widgetColor;
    }
    if (ovr.widgetCapsuleGroups) {
      resolved.widgetCapsuleGroups = *ovr.widgetCapsuleGroups;
    }
    if (ovr.widgetCapsulePadding) {
      resolved.widgetCapsulePadding = std::clamp(static_cast<float>(*ovr.widgetCapsulePadding), 0.0f, 48.0f);
    }
    if (ovr.widgetCapsuleOpacity) {
      resolved.widgetCapsuleOpacity = std::clamp(static_cast<float>(*ovr.widgetCapsuleOpacity), 0.0f, 1.0f);
    }
    return resolved;
  }

  bool barMonitorOverrideEqual(const BarConfig& base, const BarMonitorOverride& a, const BarMonitorOverride& b) {
    return a.match == b.match &&
           barBaseConfigEqual(applyMonitorOverrideForComparison(base, a), applyMonitorOverrideForComparison(base, b));
  }

  bool barConfigEqual(const BarConfig& a, const BarConfig& b) {
    return barBaseConfigEqual(a, b) && vectorEqual(a.monitorOverrides, b.monitorOverrides,
                                                   [&a](const BarMonitorOverride& lhs, const BarMonitorOverride& rhs) {
                                                     return barMonitorOverrideEqual(a, lhs, rhs);
                                                   });
  }

  bool widgetConfigEqual(const WidgetConfig& a, const WidgetConfig& b) {
    return a.type == b.type && widgetSettingsEqual(a.settings, b.settings);
  }

  bool widgetMapEqual(const std::unordered_map<std::string, WidgetConfig>& a,
                      const std::unordered_map<std::string, WidgetConfig>& b) {
    if (a.size() != b.size()) {
      return false;
    }
    for (const auto& [key, value] : a) {
      const auto it = b.find(key);
      if (it == b.end() || !widgetConfigEqual(value, it->second)) {
        return false;
      }
    }
    return true;
  }

  bool wallpaperMonitorOverrideEqual(const WallpaperMonitorOverride& a, const WallpaperMonitorOverride& b) {
    return a.match == b.match && a.enabled == b.enabled && optionalColorSpecEqual(a.fillColor, b.fillColor) &&
           a.directory == b.directory && a.directoryLight == b.directoryLight && a.directoryDark == b.directoryDark;
  }

  bool wallpaperConfigEqual(const WallpaperConfig& a, const WallpaperConfig& b) {
    return a.enabled == b.enabled && a.fillMode == b.fillMode && optionalColorSpecEqual(a.fillColor, b.fillColor) &&
           a.transitions == b.transitions && nearlyEqual(a.transitionDurationMs, b.transitionDurationMs) &&
           nearlyEqual(a.edgeSmoothness, b.edgeSmoothness) && a.directory == b.directory &&
           a.directoryLight == b.directoryLight && a.directoryDark == b.directoryDark &&
           a.automation.enabled == b.automation.enabled &&
           a.automation.intervalMinutes == b.automation.intervalMinutes && a.automation.order == b.automation.order &&
           a.automation.recursive == b.automation.recursive &&
           vectorEqual(a.monitorOverrides, b.monitorOverrides, wallpaperMonitorOverrideEqual);
  }

  bool dockConfigEqual(const DockConfig& a, const DockConfig& b) {
    return a.enabled == b.enabled && a.position == b.position && a.activeMonitorOnly == b.activeMonitorOnly &&
           a.iconSize == b.iconSize && a.padding == b.padding && a.itemSpacing == b.itemSpacing &&
           nearlyEqual(a.backgroundOpacity, b.backgroundOpacity) && a.radius == b.radius &&
           a.marginEnds == b.marginEnds && a.marginEdge == b.marginEdge && a.shadow == b.shadow &&
           a.showRunning == b.showRunning && a.autoHide == b.autoHide && a.reserveSpace == b.reserveSpace &&
           nearlyEqual(a.activeScale, b.activeScale) && nearlyEqual(a.inactiveScale, b.inactiveScale) &&
           nearlyEqual(a.activeOpacity, b.activeOpacity) && nearlyEqual(a.inactiveOpacity, b.inactiveOpacity) &&
           a.showInstanceCount == b.showInstanceCount && a.pinned == b.pinned;
  }

  bool shellConfigEqual(const ShellConfig& a, const ShellConfig& b) {
    return nearlyEqual(a.uiScale, b.uiScale) && a.fontFamily == b.fontFamily && a.lang == b.lang &&
           a.offlineMode == b.offlineMode && a.telemetryEnabled == b.telemetryEnabled &&
           a.polkitAgent == b.polkitAgent && a.passwordMaskStyle == b.passwordMaskStyle &&
           a.animation.enabled == b.animation.enabled && nearlyEqual(a.animation.speed, b.animation.speed) &&
           a.avatarPath == b.avatarPath && a.settingsShowAdvanced == b.settingsShowAdvanced &&
           a.showLocation == b.showLocation && a.clipboardAutoPaste == b.clipboardAutoPaste &&
           a.shadow.blur == b.shadow.blur && a.shadow.offsetX == b.shadow.offsetX &&
           a.shadow.offsetY == b.shadow.offsetY && nearlyEqual(a.shadow.alpha, b.shadow.alpha) &&
           a.panel.backgroundBlur == b.panel.backgroundBlur && a.screenCorners.enabled == b.screenCorners.enabled &&
           a.screenCorners.size == b.screenCorners.size && a.mpris.blacklist == b.mpris.blacklist;
  }

  bool notificationConfigEqual(const NotificationConfig& a, const NotificationConfig& b) {
    return a.enableDaemon == b.enableDaemon && a.position == b.position && a.layer == b.layer &&
           nearlyEqual(a.backgroundOpacity, b.backgroundOpacity) && a.monitors == b.monitors;
  }

  bool audioConfigEqual(const AudioConfig& a, const AudioConfig& b) {
    return a.enableOverdrive == b.enableOverdrive && a.enableSounds == b.enableSounds &&
           nearlyEqual(a.soundVolume, b.soundVolume) && a.volumeChangeSound == b.volumeChangeSound &&
           a.notificationSound == b.notificationSound;
  }

  bool nightLightConfigEqual(const NightLightConfig& a, const NightLightConfig& b) {
    return a.enabled == b.enabled && a.force == b.force && a.useWeatherLocation == b.useWeatherLocation &&
           a.startTime == b.startTime && a.stopTime == b.stopTime && optionalDoubleEqual(a.latitude, b.latitude) &&
           optionalDoubleEqual(a.longitude, b.longitude) && a.dayTemperature == b.dayTemperature &&
           a.nightTemperature == b.nightTemperature;
  }

  bool idleConfigEqual(const IdleConfig& a, const IdleConfig& b) {
    return vectorEqual(a.behaviors, b.behaviors, [](const IdleBehaviorConfig& lhs, const IdleBehaviorConfig& rhs) {
      return lhs.name == rhs.name && lhs.enabled == rhs.enabled && lhs.timeoutSeconds == rhs.timeoutSeconds &&
             lhs.command == rhs.command && lhs.resumeCommand == rhs.resumeCommand;
    });
  }

  bool themeConfigEqual(const ThemeConfig& a, const ThemeConfig& b) {
    return a.source == b.source && a.builtinPalette == b.builtinPalette && a.communityPalette == b.communityPalette &&
           a.wallpaperScheme == b.wallpaperScheme && a.mode == b.mode &&
           a.templates.enableBuiltinTemplates == b.templates.enableBuiltinTemplates &&
           a.templates.builtinIds == b.templates.builtinIds &&
           a.templates.enableCommunityTemplates == b.templates.enableCommunityTemplates &&
           a.templates.communityIds == b.templates.communityIds &&
           a.templates.enableUserTemplates == b.templates.enableUserTemplates &&
           a.templates.userConfig == b.templates.userConfig;
  }

  bool configEqual(const Config& a, const Config& b) {
    return vectorEqual(a.bars, b.bars, barConfigEqual) && widgetMapEqual(a.widgets, b.widgets) &&
           wallpaperConfigEqual(a.wallpaper, b.wallpaper) && a.backdrop.enabled == b.backdrop.enabled &&
           nearlyEqual(a.backdrop.blurIntensity, b.backdrop.blurIntensity) &&
           nearlyEqual(a.backdrop.tintIntensity, b.backdrop.tintIntensity) && dockConfigEqual(a.dock, b.dock) &&
           a.desktopWidgets == b.desktopWidgets && shellConfigEqual(a.shell, b.shell) &&
           a.osd.position == b.osd.position && notificationConfigEqual(a.notification, b.notification) &&
           a.weather.enabled == b.weather.enabled && a.weather.autoLocate == b.weather.autoLocate &&
           a.weather.effects == b.weather.effects && a.weather.address == b.weather.address &&
           a.weather.refreshMinutes == b.weather.refreshMinutes && a.weather.unit == b.weather.unit &&
           a.system.monitor.enabled == b.system.monitor.enabled && audioConfigEqual(a.audio, b.audio) &&
           a.brightness == b.brightness && a.keybinds.validate == b.keybinds.validate &&
           a.keybinds.cancel == b.keybinds.cancel && a.keybinds.left == b.keybinds.left &&
           a.keybinds.right == b.keybinds.right && a.keybinds.up == b.keybinds.up &&
           a.keybinds.down == b.keybinds.down && nightLightConfigEqual(a.nightlight, b.nightlight) &&
           idleConfigEqual(a.idle, b.idle) && a.hooks == b.hooks && themeConfigEqual(a.theme, b.theme) &&
           a.controlCenter == b.controlCenter;
  }

  toml::table* ensureTable(toml::table& parent, std::string_view key) {
    if (auto* existing = parent.get_as<toml::table>(key)) {
      return existing;
    }
    auto [it, _] = parent.insert_or_assign(key, toml::table{});
    return it->second.as_table();
  }

  void insertOverrideValue(toml::table& table, std::string_view key, const ConfigOverrideValue& value) {
    std::visit(
        [&](const auto& concrete) {
          using T = std::decay_t<decltype(concrete)>;
          if constexpr (std::is_same_v<T, std::vector<std::string>>) {
            toml::array array;
            for (const auto& item : concrete) {
              array.push_back(item);
            }
            table.insert_or_assign(key, std::move(array));
          } else {
            table.insert_or_assign(key, concrete);
          }
        },
        value);
  }

  std::vector<std::string> barOrderNames(const std::vector<BarConfig>& bars) {
    std::vector<std::string> order;
    order.reserve(bars.size());
    for (const auto& bar : bars) {
      order.push_back(bar.name);
    }
    return order;
  }

  bool setBarOverrideOrder(toml::table& root, const std::vector<std::string>& order) {
    auto* barRoot = ensureTable(root, "bar");
    if (barRoot == nullptr) {
      return false;
    }
    insertOverrideValue(*barRoot, "order", order);
    return true;
  }

  const toml::node* findOverrideNode(const toml::table& root, const std::vector<std::string>& path) {
    const toml::table* table = &root;
    for (std::size_t i = 0; i < path.size(); ++i) {
      if (i + 1 == path.size()) {
        return table->get(path[i]);
      }
      auto* next = table->get_as<toml::table>(path[i]);
      if (next == nullptr) {
        return nullptr;
      }
      table = next;
    }
    return nullptr;
  }

  void pruneEmptyOverrideTables(toml::table& root, const std::vector<std::string>& changedPath,
                                std::size_t preserveDepth = 0) {
    if (changedPath.size() < 2) {
      return;
    }

    for (std::size_t depth = changedPath.size() - 1; depth > 0; --depth) {
      if (preserveDepth > 0 && depth <= preserveDepth) {
        break;
      }

      toml::table* parent = &root;
      for (std::size_t i = 0; i + 1 < depth; ++i) {
        parent = parent->get_as<toml::table>(changedPath[i]);
        if (parent == nullptr) {
          return;
        }
      }

      auto* node = parent->get(changedPath[depth - 1]);
      auto* table = node != nullptr ? node->as_table() : nullptr;
      if (table == nullptr || !table->empty()) {
        break;
      }
      parent->erase(changedPath[depth - 1]);
    }
  }

  bool eraseOverridePath(toml::table& root, const std::vector<std::string>& path, std::size_t preserveDepth = 0) {
    if (path.empty()) {
      return false;
    }

    toml::table* table = &root;
    for (std::size_t i = 0; i + 1 < path.size(); ++i) {
      auto* next = table->get_as<toml::table>(path[i]);
      if (next == nullptr) {
        return false;
      }
      table = next;
    }

    if (table->erase(path.back()) == 0) {
      return false;
    }
    pruneEmptyOverrideTables(root, path, preserveDepth);
    return true;
  }

  std::vector<std::filesystem::path> sortedConfigTomlFiles(std::string_view configDir) {
    std::vector<std::filesystem::path> files;
    if (configDir.empty()) {
      return files;
    }

    std::error_code ec;
    if (!std::filesystem::is_directory(configDir, ec) || ec) {
      return files;
    }
    for (const auto& entry : std::filesystem::directory_iterator(configDir, ec)) {
      if (entry.is_regular_file() && entry.path().extension() == ".toml") {
        files.push_back(entry.path());
      }
    }
    std::sort(files.begin(), files.end());
    return files;
  }
} // namespace

void ConfigService::setThemeMode(ThemeMode mode) {
  if (m_overridesPath.empty()) {
    return;
  }

  auto* themeTbl = ensureTable(m_overridesTable, "theme");
  themeTbl->insert_or_assign("mode", std::string(enumToKey(kThemeModes, mode)));

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;

  // Rebuild Config and fan out reload callbacks so ThemeService transitions.
  loadAll();
  fireReloadCallbacks();
}

void ConfigService::setDockEnabled(bool enabled) {
  if (m_overridesPath.empty()) {
    return;
  }

  auto* dockTbl = ensureTable(m_overridesTable, "dock");
  const auto existing = (*dockTbl)["enabled"].value<bool>();
  if (existing.has_value() && *existing == enabled && m_config.dock.enabled == enabled) {
    return;
  }

  dockTbl->insert_or_assign("enabled", enabled);

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;

  loadAll();
  fireReloadCallbacks();
}

bool ConfigService::markSetupWizardCompleted() {
  if (m_setupWizardCompleted) {
    return true;
  }

  m_setupWizardCompleted = true;
  if (!writeOverridesToFile()) {
    m_setupWizardCompleted = false;
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  return true;
}

bool ConfigService::hasOverride(const std::vector<std::string>& path) const {
  if (path.empty()) {
    return false;
  }
  return findOverrideNode(m_overridesTable, path) != nullptr;
}

bool ConfigService::hasEffectiveOverride(const std::vector<std::string>& path) const {
  if (path.empty() || findOverrideNode(m_overridesTable, path) == nullptr) {
    return false;
  }

  const std::string key = overrideCacheKey(path);
  if (const auto it = m_effectiveOverrideCache.find(key); it != m_effectiveOverrideCache.end()) {
    return it->second;
  }

  const bool effective = overridePathEffectiveInTable(path, m_overridesTable, &m_config);
  m_effectiveOverrideCache[key] = effective;
  return effective;
}

std::size_t ConfigService::overridePreserveDepthForPath(const std::vector<std::string>& path) const {
  if (path.size() > 4 && path[0] == "bar" && path[2] == "monitor" && isOverrideOnlyMonitorOverride(path[1], path[3])) {
    return 4;
  }
  if (path.size() > 2 && path[0] == "bar" && isOverrideOnlyBar(path[1])) {
    return 2;
  }
  return 0;
}

std::optional<Config> ConfigService::configForOverrides(const toml::table& overrides) const {
  Config parsed;
  seedBuiltinWidgets(parsed);

  const auto files = sortedConfigTomlFiles(m_configDir);
  toml::table merged;
  for (const auto& path : files) {
    try {
      auto tbl = toml::parse_file(path.string());
      deepMerge(merged, tbl);
    } catch (const toml::parse_error& e) {
      kLog.warn("skipping parse error in effective override comparison {}: {}", path.filename().string(),
                e.description());
    }
  }

  deepMerge(merged, overrides);
  if (files.empty() && overrides.empty()) {
    parsed.idle.behaviors.push_back(IdleBehaviorConfig{
        .name = "lock",
        .enabled = false,
        .timeoutSeconds = 660,
        .command = "noctalia:screen-lock",
        .resumeCommand = "",
    });
    parsed.bars.push_back(BarConfig{});
    return parsed;
  }

  try {
    parseTableInto(merged, parsed, false);
  } catch (const std::exception& e) {
    kLog.warn("effective override comparison parse failed: {}", e.what());
    return std::nullopt;
  }
  return parsed;
}

bool ConfigService::overridePathEffectiveInTable(const std::vector<std::string>& path, const toml::table& overrides,
                                                 const Config* parsedWith) const {
  if (path.empty() || findOverrideNode(overrides, path) == nullptr) {
    return false;
  }

  std::optional<Config> ownedWithOverride;
  if (parsedWith == nullptr) {
    ownedWithOverride = configForOverrides(overrides);
    if (!ownedWithOverride.has_value()) {
      return true;
    }
    parsedWith = &*ownedWithOverride;
  }

  toml::table withoutTable = overrides;
  eraseOverridePath(withoutTable, path, overridePreserveDepthForPath(path));
  auto withoutOverride = configForOverrides(withoutTable);
  if (!withoutOverride.has_value()) {
    return true;
  }

  return !configEqual(*parsedWith, *withoutOverride);
}

bool ConfigService::isOverrideOnlyBar(std::string_view name) const {
  if (name.empty() || !hasOverride({"bar", std::string(name)})) {
    return false;
  }
  return !m_configFileBarNames.contains(std::string(name));
}

bool ConfigService::canMoveBarOverride(std::string_view name, int direction) const {
  if (direction == 0 || name.empty()) {
    return false;
  }

  const auto barIt = std::find_if(m_config.bars.begin(), m_config.bars.end(),
                                  [name](const BarConfig& bar) { return bar.name == name; });
  if (barIt == m_config.bars.end()) {
    return false;
  }

  if (direction < 0) {
    return barIt != m_config.bars.begin();
  }

  return std::next(barIt) != m_config.bars.end();
}

bool ConfigService::canDeleteBarOverride(std::string_view name) const {
  return m_config.bars.size() > 1 && isOverrideOnlyBar(name);
}

bool ConfigService::isOverrideOnlyMonitorOverride(std::string_view barName, std::string_view match) const {
  if (barName.empty() || match.empty() || !hasOverride({"bar", std::string(barName), "monitor", std::string(match)})) {
    return false;
  }

  const auto barIt = m_configFileMonitorOverrideNames.find(std::string(barName));
  if (barIt == m_configFileMonitorOverrideNames.end()) {
    return true;
  }
  return !barIt->second.contains(std::string(match));
}

bool ConfigService::createBarOverride(std::string_view name) {
  if (m_overridesPath.empty() || name.empty()) {
    return false;
  }

  for (const auto& bar : m_config.bars) {
    if (bar.name == name) {
      return false;
    }
  }

  auto* barRoot = ensureTable(m_overridesTable, "bar");
  if (barRoot == nullptr || barRoot->get(std::string(name)) != nullptr) {
    return false;
  }

  if (m_configFileBarNames.empty() && barRoot->empty() && m_config.bars.size() == 1 &&
      m_config.bars.front().name == "default") {
    auto* defaultBar = ensureTable(*barRoot, "default");
    if (defaultBar == nullptr) {
      return false;
    }
    defaultBar->insert_or_assign("enabled", m_config.bars.front().enabled);
  }

  auto* barTbl = ensureTable(*barRoot, name);
  if (barTbl == nullptr) {
    return false;
  }
  barTbl->insert_or_assign("enabled", true);

  auto order = barOrderNames(m_config.bars);
  order.push_back(std::string(name));
  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::moveBarOverride(std::string_view name, int direction) {
  if (!canMoveBarOverride(name, direction)) {
    return false;
  }

  auto order = barOrderNames(m_config.bars);
  const auto currentIt = std::find(order.begin(), order.end(), std::string(name));
  if (currentIt == order.end()) {
    return false;
  }

  if (direction < 0) {
    std::iter_swap(currentIt, std::prev(currentIt));
  } else {
    std::iter_swap(currentIt, std::next(currentIt));
  }

  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::renameBarOverride(std::string_view oldName, std::string_view newName) {
  if (oldName.empty() || newName.empty() || oldName == newName || !isOverrideOnlyBar(oldName)) {
    return false;
  }

  for (const auto& bar : m_config.bars) {
    if (bar.name == newName) {
      return false;
    }
  }

  auto order = barOrderNames(m_config.bars);
  for (auto& item : order) {
    if (item == oldName) {
      item = std::string(newName);
      break;
    }
  }
  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }

  return renameOverrideTable({"bar", std::string(oldName)}, {"bar", std::string(newName)});
}

bool ConfigService::deleteBarOverride(std::string_view name) {
  if (!canDeleteBarOverride(name)) {
    return false;
  }
  auto order = barOrderNames(m_config.bars);
  std::erase(order, std::string(name));
  if (!setBarOverrideOrder(m_overridesTable, order)) {
    return false;
  }
  return clearOverride({"bar", std::string(name)});
}

bool ConfigService::createMonitorOverride(std::string_view barName, std::string_view match) {
  if (m_overridesPath.empty() || barName.empty() || match.empty()) {
    return false;
  }

  const auto barIt = std::find_if(m_config.bars.begin(), m_config.bars.end(),
                                  [barName](const BarConfig& bar) { return bar.name == barName; });
  if (barIt == m_config.bars.end()) {
    return false;
  }
  const auto monitorIt = std::find_if(barIt->monitorOverrides.begin(), barIt->monitorOverrides.end(),
                                      [match](const BarMonitorOverride& ovr) { return ovr.match == match; });
  if (monitorIt != barIt->monitorOverrides.end()) {
    return false;
  }

  auto* barRoot = ensureTable(m_overridesTable, "bar");
  if (barRoot == nullptr) {
    return false;
  }
  auto* barTbl = ensureTable(*barRoot, barName);
  if (barTbl == nullptr) {
    return false;
  }
  auto* monitorRoot = ensureTable(*barTbl, "monitor");
  if (monitorRoot == nullptr || monitorRoot->get(std::string(match)) != nullptr) {
    return false;
  }
  if (ensureTable(*monitorRoot, match) == nullptr) {
    return false;
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::renameMonitorOverride(std::string_view barName, std::string_view oldMatch,
                                          std::string_view newMatch) {
  if (barName.empty() || oldMatch.empty() || newMatch.empty() || oldMatch == newMatch ||
      !isOverrideOnlyMonitorOverride(barName, oldMatch)) {
    return false;
  }

  const auto barIt = std::find_if(m_config.bars.begin(), m_config.bars.end(),
                                  [barName](const BarConfig& bar) { return bar.name == barName; });
  if (barIt == m_config.bars.end()) {
    return false;
  }
  const auto monitorIt = std::find_if(barIt->monitorOverrides.begin(), barIt->monitorOverrides.end(),
                                      [newMatch](const BarMonitorOverride& ovr) { return ovr.match == newMatch; });
  if (monitorIt != barIt->monitorOverrides.end()) {
    return false;
  }

  return renameOverrideTable({"bar", std::string(barName), "monitor", std::string(oldMatch)},
                             {"bar", std::string(barName), "monitor", std::string(newMatch)});
}

bool ConfigService::deleteMonitorOverride(std::string_view barName, std::string_view match) {
  if (!isOverrideOnlyMonitorOverride(barName, match)) {
    return false;
  }
  return clearOverride({"bar", std::string(barName), "monitor", std::string(match)});
}

bool ConfigService::setOverride(const std::vector<std::string>& path, ConfigOverrideValue value) {
  if (m_overridesPath.empty() || path.empty()) {
    return false;
  }

  toml::table* table = &m_overridesTable;
  for (std::size_t i = 0; i + 1 < path.size(); ++i) {
    table = ensureTable(*table, path[i]);
    if (table == nullptr) {
      return false;
    }
  }

  insertOverrideValue(*table, path.back(), value);
  if (!overridePathEffectiveInTable(path, m_overridesTable)) {
    eraseOverridePath(m_overridesTable, path, overridePreserveDepthForPath(path));
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  extractWallpaperFromOverrides();
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::clearOverride(const std::vector<std::string>& path) {
  if (m_overridesPath.empty() || path.empty()) {
    return false;
  }

  if (!eraseOverridePath(m_overridesTable, path, overridePreserveDepthForPath(path))) {
    return false;
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  extractWallpaperFromOverrides();
  loadAll();
  fireReloadCallbacks();
  return true;
}

bool ConfigService::renameOverrideTable(const std::vector<std::string>& oldPath,
                                        const std::vector<std::string>& newPath) {
  if (m_overridesPath.empty() || oldPath.empty() || newPath.empty() || oldPath == newPath) {
    return false;
  }

  toml::table* oldParent = &m_overridesTable;
  for (std::size_t i = 0; i + 1 < oldPath.size(); ++i) {
    auto* next = oldParent->get_as<toml::table>(oldPath[i]);
    if (next == nullptr) {
      return false;
    }
    oldParent = next;
  }

  toml::node* oldNode = oldParent->get(oldPath.back());
  if (oldNode == nullptr || oldNode->as_table() == nullptr) {
    return false;
  }

  toml::table* newParent = &m_overridesTable;
  for (std::size_t i = 0; i + 1 < newPath.size(); ++i) {
    newParent = ensureTable(*newParent, newPath[i]);
    if (newParent == nullptr) {
      return false;
    }
  }

  if (newParent->get(newPath.back()) != nullptr) {
    return false;
  }

  if (oldParent == newParent) {
    std::vector<std::pair<std::string, const toml::node*>> entries;
    entries.reserve(oldParent->size());
    for (const auto& [key, node] : *oldParent) {
      std::string entryKey(key.str());
      if (entryKey == oldPath.back()) {
        entryKey = newPath.back();
      }
      entries.emplace_back(std::move(entryKey), &node);
    }

    toml::table renamed;
    for (const auto& [key, node] : entries) {
      renamed.insert_or_assign(key, *node);
    }
    *oldParent = std::move(renamed);
  } else {
    newParent->insert_or_assign(newPath.back(), *oldNode);
    oldParent->erase(oldPath.back());
    pruneEmptyOverrideTables(m_overridesTable, oldPath);
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return false;
  }

  m_ownOverridesWritePending = true;
  extractWallpaperFromOverrides();
  loadAll();
  fireReloadCallbacks();
  return true;
}

std::string ConfigService::getWallpaperPath(const std::string& connectorName) const {
  auto it = m_monitorWallpaperPaths.find(connectorName);
  if (it != m_monitorWallpaperPaths.end()) {
    return it->second;
  }
  return m_defaultWallpaperPath;
}

std::string ConfigService::getDefaultWallpaperPath() const { return m_defaultWallpaperPath; }

void ConfigService::setWallpaperChangeCallback(ChangeCallback callback) {
  m_wallpaperChangeCallback = std::move(callback);
}

void ConfigService::setWallpaperPath(const std::optional<std::string>& connectorName, const std::string& path) {
  if (m_overridesPath.empty()) {
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

  // Mirror the change into the overrides table so writeOverridesToFile() serializes it.
  auto* wallpaperTbl = ensureTable(m_overridesTable, "wallpaper");
  if (connectorName.has_value()) {
    auto* monitorsTbl = ensureTable(*wallpaperTbl, "monitors");
    auto* monTbl = ensureTable(*monitorsTbl, *connectorName);
    monTbl->insert_or_assign("path", path);
  } else {
    auto* defaultTbl = ensureTable(*wallpaperTbl, "default");
    defaultTbl->insert_or_assign("path", path);
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;
  if (m_wallpaperBatchDepth > 0) {
    m_wallpaperBatchDirty = true;
    return;
  }
  if (m_wallpaperChangeCallback) {
    m_wallpaperChangeCallback();
  }
}

void ConfigService::extractWallpaperFromOverrides() {
  m_defaultWallpaperPath.clear();
  m_monitorWallpaperPaths.clear();

  if (auto* wpDefault = m_overridesTable["wallpaper"]["default"].as_table()) {
    if (auto v = (*wpDefault)["path"].value<std::string>()) {
      m_defaultWallpaperPath = FileUtils::expandUserPath(*v).string();
    }
  }
  if (auto* monitors = m_overridesTable["wallpaper"]["monitors"].as_table()) {
    for (const auto& [key, value] : *monitors) {
      if (auto* monTbl = value.as_table()) {
        if (auto v = (*monTbl)["path"].value<std::string>()) {
          m_monitorWallpaperPaths[std::string(key.str())] = FileUtils::expandUserPath(*v).string();
        }
      }
    }
  }
}

bool ConfigService::writeOverridesToFile() {
  if (m_overridesPath.empty()) {
    return false;
  }
  toml::table output = m_overridesTable;
  if (m_setupWizardCompleted) {
    auto* state = ensureTable(output, kInternalStateTable);
    state->insert_or_assign(kSetupWizardCompletedKey, true);
  }

  const std::string tmpPath = m_overridesPath + ".tmp";
  {
    std::ofstream out(tmpPath, std::ios::trunc);
    if (!out.is_open()) {
      return false;
    }
    out << toml::toml_formatter{output,
                                toml::toml_formatter::default_flags & ~toml::format_flags::allow_literal_strings};
    if (!out.good()) {
      return false;
    }
  }
  std::error_code ec;
  std::filesystem::rename(tmpPath, m_overridesPath, ec);
  if (ec) {
    std::filesystem::remove(tmpPath, ec);
    return false;
  }
  return true;
}
