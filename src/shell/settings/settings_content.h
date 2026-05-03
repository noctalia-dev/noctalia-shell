#pragma once

#include "config/config_service.h"
#include "shell/settings/settings_registry.h"

#include <cstddef>
#include <functional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

class Flex;
class InputArea;

namespace settings {

  struct SettingsContentContext {
    const Config& config;
    ConfigService* configService = nullptr;
    float scale = 1.0f;
    std::string_view searchQuery;
    std::string_view selectedSection;
    const BarConfig* selectedBar = nullptr;
    const BarMonitorOverride* selectedMonitorOverride = nullptr;
    bool showAdvanced = false;
    bool showOverriddenOnly = false;

    std::string& openWidgetPickerPath;
    std::string& openSearchPickerPath;
    std::string& editingWidgetName;
    std::string& pendingDeleteWidgetName;
    std::string& pendingDeleteWidgetSettingPath;
    std::string& renamingWidgetName;
    std::string& creatingWidgetType;

    std::function<void()> requestRebuild;
    std::function<void()> requestContentRebuild;
    std::function<void()> resetContentScroll;
    std::function<void(InputArea*)> focusArea;
    std::function<void(std::vector<std::string>, ConfigOverrideValue)> setOverride;
    std::function<void(std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>)> setOverrides;
    std::function<void(std::vector<std::string>)> clearOverride;
    std::function<void(std::string, std::string, std::vector<std::pair<std::vector<std::string>, ConfigOverrideValue>>)>
        renameWidgetInstance;
  };

  std::size_t addSettingsContentSections(Flex& content, const std::vector<SettingEntry>& registry,
                                         SettingsContentContext ctx);

} // namespace settings
