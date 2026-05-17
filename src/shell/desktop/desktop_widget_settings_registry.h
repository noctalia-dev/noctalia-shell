#pragma once

#include "shell/settings/widget_settings_registry.h"

#include <string_view>
#include <vector>

namespace desktop_settings {

  struct DesktopWidgetTypeSpec {
    std::string_view type;
    std::string_view labelKey;
  };

  [[nodiscard]] const std::vector<DesktopWidgetTypeSpec>& desktopWidgetTypeSpecs();
  [[nodiscard]] std::vector<settings::WidgetSettingSpec> desktopWidgetSettingSpecs(std::string_view type);
  [[nodiscard]] std::vector<settings::WidgetSettingSpec> commonDesktopWidgetSettingSpecs();

} // namespace desktop_settings
