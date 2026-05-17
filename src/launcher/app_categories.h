#pragma once

#include "launcher/launcher_provider.h"
#include "system/desktop_entry.h"

#include <string_view>
#include <vector>

namespace LauncherAppCategories {
  inline constexpr std::string_view All = "all";
}

[[nodiscard]] std::vector<LauncherCategory> availableLauncherAppCategories(const std::vector<DesktopEntry>& entries);
[[nodiscard]] bool launcherAppEntryMatchesCategory(const DesktopEntry& entry, std::string_view category);
