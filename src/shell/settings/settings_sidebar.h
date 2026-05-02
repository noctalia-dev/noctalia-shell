#pragma once

#include "config/config_service.h"
#include "ui/controls/scroll_view.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

class Flex;

namespace settings {

  struct SettingsSidebarContext {
    const Config& config;
    const std::vector<std::string>& sections;
    const std::vector<std::string>& availableBars;
    float scale = 1.0f;
    bool globalSearchActive = false;

    ScrollViewState& sidebarScrollState;
    ScrollViewState& contentScrollState;
    std::string& selectedSection;
    std::string& selectedBarName;
    std::string& selectedMonitorOverride;
    std::string& creatingBarName;
    std::string& creatingMonitorOverrideBarName;
    std::string& creatingMonitorOverrideMatch;

    std::function<void()> clearTransientState;
    std::function<void()> clearSearchQuery;
    std::function<void()> requestRebuild;
    std::function<void(std::string)> createBar;
    std::function<void(std::string, std::string)> createMonitorOverride;
  };

  [[nodiscard]] std::unique_ptr<Flex> buildSettingsSidebar(SettingsSidebarContext ctx);

} // namespace settings
