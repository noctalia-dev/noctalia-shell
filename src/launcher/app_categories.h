#pragma once

#include "system/desktop_entry.h"

#include <string>
#include <string_view>
#include <vector>

struct LauncherAppCategory {
  std::string id;
  std::string labelKey;
  std::string glyphName;
};

namespace LauncherAppCategories {
  inline constexpr std::string_view All = "all";
}

[[nodiscard]] std::vector<LauncherAppCategory> availableLauncherAppCategories(const std::vector<DesktopEntry>& entries);
[[nodiscard]] bool launcherAppEntryMatchesCategory(const DesktopEntry& entry, std::string_view category);
