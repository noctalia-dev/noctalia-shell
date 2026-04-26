#pragma once

#include "config/config_service.h"

#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

namespace settings {

  struct ToggleSetting {
    bool checked = false;
  };

  struct SelectOption {
    std::string value;
    std::string label;
  };

  struct SelectSetting {
    std::vector<SelectOption> options;
    std::string selectedValue;
    bool clearOnEmpty = false;
  };

  struct SliderSetting {
    float value = 0.0f;
    float minValue = 0.0f;
    float maxValue = 1.0f;
    float step = 0.01f;
    bool integerValue = false;
  };

  struct TextSetting {
    std::string value;
    std::string placeholder;
  };

  struct OptionalNumberSetting {
    std::optional<double> value;
    double minValue = 0.0;
    double maxValue = 1.0;
    std::string placeholder;
  };

  struct ListSetting {
    std::vector<std::string> items;
  };

  using SettingControl =
      std::variant<ToggleSetting, SelectSetting, SliderSetting, TextSetting, OptionalNumberSetting, ListSetting>;

  struct SettingEntry {
    std::string section;
    std::string group;
    std::string title;
    std::string subtitle;
    std::vector<std::string> path;
    SettingControl control;
    bool advanced = false;
    std::string searchText;
  };

  [[nodiscard]] const BarConfig* findBar(const Config& cfg, std::string_view name);
  [[nodiscard]] const BarMonitorOverride* findMonitorOverride(const BarConfig& bar, std::string_view match);
  [[nodiscard]] std::vector<std::string> barNames(const Config& cfg);
  [[nodiscard]] std::vector<SettingEntry>
  buildSettingsRegistry(const Config& cfg, const BarConfig* selectedBar,
                        const BarMonitorOverride* selectedMonitorOverride = nullptr);
  [[nodiscard]] bool matchesSettingQuery(const SettingEntry& entry, std::string_view query);

} // namespace settings
