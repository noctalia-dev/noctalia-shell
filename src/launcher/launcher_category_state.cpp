#include "launcher/launcher_category_state.h"

#include <utility>

namespace LauncherCategoryState {

  LauncherProvider* singleCategoryProvider(const std::vector<std::unique_ptr<LauncherProvider>>& providers) {
    LauncherProvider* candidate = nullptr;
    for (const auto& provider : providers) {
      if (provider == nullptr || !provider->prefix().empty() || provider->availableCategories().empty()) {
        continue;
      }
      if (candidate != nullptr) {
        return nullptr;
      }
      candidate = provider.get();
    }
    return candidate;
  }

  CategoryTabsState resolveTabs(const std::vector<std::unique_ptr<LauncherProvider>>& providers, std::string_view query,
                                bool enabled) {
    CategoryTabsState state;
    if (!enabled || !query.empty()) {
      resetHiddenCategoryFilters(providers);
      return state;
    }

    for (const auto& provider : providers) {
      if (provider == nullptr || !provider->prefix().empty()) {
        continue;
      }

      auto categories = provider->availableCategories();
      if (categories.empty()) {
        continue;
      }

      if (state.provider != nullptr) {
        resetHiddenCategoryFilters(providers);
        return {};
      }

      state.provider = provider.get();
      state.categories = std::move(categories);
    }

    state.visible = state.provider != nullptr && state.categories.size() > 1;
    if (!state.visible) {
      resetHiddenCategoryFilters(providers);
    }
    return state;
  }

  void resetHiddenCategoryFilters(const std::vector<std::unique_ptr<LauncherProvider>>& providers) {
    for (const auto& provider : providers) {
      if (provider != nullptr) {
        provider->resetCategory();
      }
    }
  }

} // namespace LauncherCategoryState
