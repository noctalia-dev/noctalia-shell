#pragma once

#include "config/config_service.h"

#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace settings {

  struct ToggleSetting {
    bool checked = false;
  };

  struct SelectSetting {
    std::vector<std::string> options;
    std::string selected;
  };

  struct SliderSetting {
    float value = 0.0f;
    float minValue = 0.0f;
    float maxValue = 1.0f;
    float step = 0.01f;
    bool integerValue = false;
  };

  using SettingControl = std::variant<ToggleSetting, SelectSetting, SliderSetting>;

  struct SettingEntry {
    std::string section;
    std::string title;
    std::string subtitle;
    std::vector<std::string> path;
    SettingControl control;
    std::string searchText;
  };

  [[nodiscard]] const BarConfig* findBar(const Config& cfg, std::string_view name);
  [[nodiscard]] std::vector<std::string> barNames(const Config& cfg);
  [[nodiscard]] std::vector<SettingEntry> buildSettingsRegistry(const Config& cfg, const BarConfig* selectedBar);
  [[nodiscard]] bool matchesSettingQuery(const SettingEntry& entry, std::string_view query);

} // namespace settings
