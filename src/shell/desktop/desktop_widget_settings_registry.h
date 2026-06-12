#pragma once

#include "config/config_types.h"
#include "shell/settings/widget_settings_registry.h"

#include <string_view>
#include <unordered_map>
#include <vector>

namespace desktop_settings {

  enum class DesktopWidgetSettingsScope {
    Widget,
    Background,
  };

  struct DesktopWidgetTypeSpec {
    std::string_view type;
    std::string_view labelKey;
  };

  [[nodiscard]] const std::vector<DesktopWidgetTypeSpec>& desktopWidgetTypeSpecs();
  [[nodiscard]] std::vector<settings::WidgetSettingSpec> desktopWidgetSettingSpecs(std::string_view type);
  [[nodiscard]] std::vector<settings::WidgetSettingSpec> commonDesktopWidgetSettingSpecs(std::string_view type = {});
  // Schema projection (per-type + common settings), consumed by `config validate`.
  [[nodiscard]] noctalia::config::schema::WidgetSettingSchema desktopWidgetSettingSchema(std::string_view type);
  void applyDesktopWidgetDefaultSettings(
      std::unordered_map<std::string, WidgetSettingValue>& settings, std::string_view type,
      DesktopWidgetSettingsScope scope
  );
  void applyAllDesktopWidgetDefaultSettings(
      std::unordered_map<std::string, WidgetSettingValue>& settings, std::string_view type
  );

} // namespace desktop_settings
