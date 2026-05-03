#pragma once

#include "config/config_service.h"
#include "ui/palette.h"

#include <functional>
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
    bool segmented = false; // render as Segmented pill group instead of dropdown Select
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
    // When non-empty, the add UI presents a Select limited to these options (minus already-added values)
    // instead of a free-form text input, and row labels resolve to the option's friendly label.
    // Useful when the catalog of valid values is known.
    std::vector<SelectOption> suggestedOptions = {};
  };

  struct ColorSetting {
    std::string hex; // current resolved value as #RRGGBB; empty when unset
    bool unset = true;
  };

  struct MultiSelectSetting {
    std::vector<SelectOption> options;
    std::vector<std::string> selectedValues;
    bool requireAtLeastOne = false; // disable removing the last selected entry
  };

  struct ButtonSetting {
    std::string label;
    std::function<void()> action;
  };

  struct ColorRolePickerSetting {
    std::vector<ColorRole> roles;
    std::string selectedValue;
    bool allowNone = false;
  };

  using SettingControl =
      std::variant<ToggleSetting, SelectSetting, SliderSetting, TextSetting, OptionalNumberSetting, ListSetting,
                   ColorSetting, MultiSelectSetting, ButtonSetting, ColorRolePickerSetting>;

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

  // Runtime conditions that gate optional sections (e.g. compositor-specific features).
  struct RegistryEnvironment {
    bool niriBackdropSupported = false;         // hide the [backdrop] section when false
    std::vector<SelectOption> availableOutputs; // monitor selectors available on this machine
    std::vector<SelectOption> communityTemplates;
  };

  [[nodiscard]] const BarConfig* findBar(const Config& cfg, std::string_view name);
  [[nodiscard]] const BarMonitorOverride* findMonitorOverride(const BarConfig& bar, std::string_view match);
  [[nodiscard]] std::vector<std::string> barNames(const Config& cfg);
  [[nodiscard]] std::vector<SettingEntry>
  buildSettingsRegistry(const Config& cfg, const BarConfig* selectedBar,
                        const BarMonitorOverride* selectedMonitorOverride = nullptr,
                        const RegistryEnvironment& env = {});
  [[nodiscard]] std::string normalizedSettingQuery(std::string_view query);
  [[nodiscard]] bool matchesNormalizedSettingQuery(const SettingEntry& entry, std::string_view normalizedQuery);
  [[nodiscard]] bool matchesSettingQuery(const SettingEntry& entry, std::string_view query);
  [[nodiscard]] std::string_view sectionGlyph(std::string_view section);

} // namespace settings
