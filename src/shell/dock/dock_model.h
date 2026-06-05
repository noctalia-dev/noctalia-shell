#pragma once

#include "config/config_types.h"
#include "system/desktop_entry.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

class CompositorPlatform;
struct wl_output;

namespace shell::dock {

  struct DockItemModel {
    DesktopEntry entry;
    std::string idLower;
    std::string startupWmClassLower;
    bool running = false;
    bool active = false;
    std::size_t instanceCount = 0;
  };

  struct DockSnapshot {
    wl_output* output = nullptr;
    wl_output* filterOutput = nullptr;
    std::string activeAppIdLower;
    std::vector<DockItemModel> items;
    std::uint64_t sourceSerial = 0;
  };

  struct DockModelDependencies {
    CompositorPlatform& platform;
    const DockConfig& config;
    wl_output* output = nullptr;
    const std::string& globalActiveIdLower;
    const std::vector<DesktopEntry>& pinnedEntries;
    std::uint64_t sourceSerial = 0;
  };

  [[nodiscard]] wl_output* dockFilterOutput(const DockConfig& cfg, wl_output* instanceOutput);
  [[nodiscard]] std::string currentActiveEntryIdLower(const CompositorPlatform& platform);
  [[nodiscard]] bool refreshPinnedAppsIfNeeded(
      const DockConfig& cfg, std::vector<std::string>& lastPinnedConfig, std::vector<DesktopEntry>& pinnedEntries,
      std::uint64_t& modelSerial, std::uint64_t& entriesVersion
  );
  [[nodiscard]] DockSnapshot buildDockSnapshot(DockModelDependencies deps);
  [[nodiscard]] bool sameDockItemSet(const DockSnapshot& a, const DockSnapshot& b);

} // namespace shell::dock
