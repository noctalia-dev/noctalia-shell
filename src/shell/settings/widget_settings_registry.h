#pragma once

#include "config/config_service.h"

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace settings {

  enum class WidgetReferenceKind : std::uint8_t {
    BuiltIn,
    Named,
    Unknown,
  };

  struct WidgetTypeSpec {
    std::string_view type;
    std::string_view labelKey;
    std::string_view categoryKey;
    bool supportsMultipleInstances = true;
    bool visibleInPicker = true;
  };

  struct WidgetReferenceInfo {
    std::string title;
    std::string detail;
    std::string badge;
    WidgetReferenceKind kind = WidgetReferenceKind::Unknown;
  };

  struct WidgetPickerEntry {
    std::string value;
    std::string label;
    std::string description;
    std::string category;
    WidgetReferenceKind kind = WidgetReferenceKind::Unknown;
  };

  enum class WidgetSettingValueType : std::uint8_t {
    Bool,
    Int,
    Double,
    String,
    StringList,
    Select,
  };

  struct WidgetSettingSelectOption {
    std::string_view value;
    std::string_view labelKey;
  };

  struct WidgetSettingSpec {
    std::string key;
    std::string labelKey;
    std::string descriptionKey;
    WidgetSettingValueType valueType = WidgetSettingValueType::String;
    WidgetSettingValue defaultValue = std::string{};
    std::optional<double> minValue;
    std::optional<double> maxValue;
    double step = 1.0;
    std::vector<WidgetSettingSelectOption> options;
    bool advanced = false;
  };

  [[nodiscard]] const std::vector<WidgetTypeSpec>& widgetTypeSpecs();
  [[nodiscard]] bool isBuiltInWidgetType(std::string_view type);
  [[nodiscard]] std::string widgetTypeForReference(const Config& cfg, std::string_view name);
  [[nodiscard]] std::string titleFromWidgetKey(std::string_view key);
  [[nodiscard]] WidgetReferenceInfo widgetReferenceInfo(const Config& cfg, std::string_view name);
  [[nodiscard]] std::vector<WidgetPickerEntry> widgetPickerEntries(const Config& cfg);
  [[nodiscard]] std::vector<WidgetSettingSpec> commonWidgetSettingSpecs();
  [[nodiscard]] std::vector<WidgetSettingSpec> widgetSettingSpecs(std::string_view type);

} // namespace settings
