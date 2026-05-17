#pragma once

#include "launcher/launcher_provider.h"

#include <memory>
#include <string_view>
#include <vector>

namespace LauncherCategoryState {

  struct CategoryTabsState {
    LauncherProvider* provider = nullptr;
    std::vector<LauncherCategory> categories;
    bool visible = false;
  };

  [[nodiscard]] LauncherProvider*
  singleCategoryProvider(const std::vector<std::unique_ptr<LauncherProvider>>& providers);

  [[nodiscard]] CategoryTabsState resolveTabs(const std::vector<std::unique_ptr<LauncherProvider>>& providers,
                                              std::string_view query, bool enabled);

  void resetHiddenCategoryFilters(const std::vector<std::unique_ptr<LauncherProvider>>& providers);

} // namespace LauncherCategoryState
