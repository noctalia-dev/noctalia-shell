#pragma once

#include "config/config_service.h"
#include "shell/settings/settings_registry.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

class Button;
class Flex;
class InputArea;
class Node;

namespace settings {

  struct BarWidgetEditorContext {
    const Config& config;
    ConfigService* configService = nullptr;
    float scale = 1.0f;
    bool showAdvanced = false;
    bool showOverriddenOnly = false;
    std::vector<SelectOption> batteryDeviceOptions;
    std::string& openWidgetPickerPath;
    std::string& editingWidgetName;
    std::string& pendingDeleteWidgetName;
    std::string& pendingDeleteWidgetSettingPath;
    std::string& renamingWidgetName;
    std::string& creatingWidgetType;

    std::function<void()> requestRebuild;
    std::function<void()> resetContentScroll;
    std::function<void(Node*)> setScrollTarget;
    std::function<void(InputArea*)> focusArea;
    std::function<void(const std::vector<std::string>&)> openWidgetAddPopup;
    std::function<void(std::vector<std::string>, ConfigOverrideValue)> setOverride;
    std::function<void(std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>)> setOverrides;
    std::function<void(std::vector<std::string>)> clearOverride;
    std::function<void(std::string, std::string, std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>)>
        renameWidgetInstance;
    std::function<std::unique_ptr<Button>(const std::vector<std::string>&)> makeResetButton;
    std::function<void(Flex&, const SettingEntry&, std::unique_ptr<Node>)> makeRow;
    std::function<std::unique_ptr<Node>(bool, std::vector<std::string>)> makeToggle;
    std::function<std::unique_ptr<Node>(const SelectSetting&, std::vector<std::string>)> makeSelect;
    std::function<std::unique_ptr<Node>(float, float, float, float, std::vector<std::string>, bool)> makeSlider;
    std::function<std::unique_ptr<Node>(const OptionalNumberSetting&, std::vector<std::string>)> makeOptionalNumber;
    std::function<std::unique_ptr<Node>(const OptionalStepperSetting&, std::vector<std::string>)> makeOptionalStepper;
    std::function<std::unique_ptr<Node>(const std::string&, const std::string&, std::vector<std::string>)> makeText;
    std::function<std::unique_ptr<Node>(const ColorRolePickerSetting&, std::vector<std::string>)> makeColorRolePicker;
    std::function<void(Flex&, const SettingEntry&, const ListSetting&)> makeListBlock;
  };

  [[nodiscard]] bool isBarWidgetListPath(const std::vector<std::string>& path);
  [[nodiscard]] bool isFirstBarWidgetListPath(const std::vector<std::string>& path);

  void addBarWidgetLaneEditor(Flex& section, const SettingEntry& entry, const BarWidgetEditorContext& ctx);

} // namespace settings
