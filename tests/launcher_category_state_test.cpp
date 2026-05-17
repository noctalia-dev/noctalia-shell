#include "launcher/launcher_category_state.h"

#include <iostream>
#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
    }
    return cond;
  }

  class TestProvider final : public LauncherProvider {
  public:
    TestProvider(std::string prefix, bool hasCategories) : m_prefix(std::move(prefix)), m_hasCategories(hasCategories) {}

    [[nodiscard]] std::string_view prefix() const override { return m_prefix; }
    [[nodiscard]] std::string_view name() const override { return "test"; }

    [[nodiscard]] std::vector<LauncherCategory> availableCategories() const override {
      m_availableCategoriesCalls += 1;
      if (!m_hasCategories) {
        return {};
      }
      return {
          {.id = "all", .labelKey = "All", .glyphName = "grid"},
          {.id = "dev", .labelKey = "Development", .glyphName = "code"},
      };
    }

    [[nodiscard]] std::string_view selectedCategory() const override { return m_selectedCategory; }
    void selectCategory(std::string_view category) override { m_selectedCategory = category; }
    void resetCategory() override {
      m_resetCount += 1;
      m_selectedCategory.clear();
    }

    [[nodiscard]] int resetCount() const noexcept { return m_resetCount; }
    [[nodiscard]] int availableCategoriesCalls() const noexcept { return m_availableCategoriesCalls; }

    [[nodiscard]] std::vector<LauncherResult> query(std::string_view /*text*/) const override { return {}; }
    bool activate(const LauncherResult& /*result*/) override { return false; }

  private:
    std::string m_prefix;
    bool m_hasCategories = false;
    std::string m_selectedCategory;
    int m_resetCount = 0;
    mutable int m_availableCategoriesCalls = 0;
  };

} // namespace

int main() {
  bool ok = true;

  std::vector<std::unique_ptr<LauncherProvider>> providers;

  auto categoryProvider = std::make_unique<TestProvider>("", true);
  auto* rawCategoryProvider = categoryProvider.get();
  rawCategoryProvider->selectCategory("dev");
  providers.push_back(std::move(categoryProvider));

  auto prefixedProvider = std::make_unique<TestProvider>("calc", true);
  auto* rawPrefixedProvider = prefixedProvider.get();
  rawPrefixedProvider->selectCategory("dev");
  providers.push_back(std::move(prefixedProvider));

  auto plainProvider = std::make_unique<TestProvider>("", false);
  auto* rawPlainProvider = plainProvider.get();
  rawPlainProvider->selectCategory("dev");
  providers.push_back(std::move(plainProvider));

  LauncherCategoryState::resetHiddenCategoryFilters(providers);

  ok &= check(rawCategoryProvider->selectedCategory().empty(),
              "unprefixed category provider should reset when category tabs are hidden");
  ok &= check(rawCategoryProvider->resetCount() == 1, "unprefixed category provider should reset exactly once");
  ok &= check(rawPrefixedProvider->selectedCategory().empty(),
              "prefixed category providers should reset when category tabs are hidden");
  ok &= check(rawPrefixedProvider->resetCount() == 1, "prefixed category providers should reset exactly once");
  ok &= check(rawPlainProvider->selectedCategory().empty(), "category reset should be cheap and safe for plain providers");
  ok &= check(rawPlainProvider->resetCount() == 1, "plain providers should receive the cheap reset hook");
  ok &= check(rawCategoryProvider->availableCategoriesCalls() == 0,
              "hidden category reset should not compute unprefixed provider categories");
  ok &= check(rawPrefixedProvider->availableCategoriesCalls() == 0,
              "hidden category reset should not compute prefixed provider categories");
  ok &= check(rawPlainProvider->availableCategoriesCalls() == 0,
              "hidden category reset should not compute plain provider categories");

  providers.clear();

  auto queryProvider = std::make_unique<TestProvider>("", true);
  auto* rawQueryProvider = queryProvider.get();
  rawQueryProvider->selectCategory("dev");
  providers.push_back(std::move(queryProvider));

  const auto queryTabs = LauncherCategoryState::resolveTabs(providers, "firefox", true);

  ok &= check(!queryTabs.visible, "typed query should hide category tabs");
  ok &= check(queryTabs.categories.empty(), "typed query should not expose stale browse categories");
  ok &= check(rawQueryProvider->selectedCategory().empty(),
              "typed query should reset the selected browse category immediately");
  ok &= check(rawQueryProvider->resetCount() == 1, "typed query should reset category filters exactly once");
  ok &= check(rawQueryProvider->availableCategoriesCalls() == 0,
              "typed query should not rebuild browse categories while tabs are hidden");

  return ok ? 0 : 1;
}
