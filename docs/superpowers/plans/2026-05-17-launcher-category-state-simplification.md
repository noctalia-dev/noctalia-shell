# Launcher Category State Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Simplify launcher category tabs so selected category state is local to `LauncherPanel`, not stored in launcher providers.

**Architecture:** Providers expose available categories and accept an optional opaque category id when queried. `LauncherPanel` owns the temporary selected category id, clears it on open/hidden tabs, and never includes app-specific category headers. Removed provider reset plumbing is removed from tests and build files.

**Tech Stack:** C++20, Meson test targets, existing launcher provider/panel classes.

---

### Task 1: Replace Reset-Plumbing Test With Category Logic Test

**Files:**
- Create: `tests/launcher_app_categories_test.cpp`
- Delete: `tests/launcher_category_state_test.cpp`
- Modify: `meson.build`

- [ ] **Step 1: Write the failing test**

Create `tests/launcher_app_categories_test.cpp` with:

```cpp
#include "launcher/app_categories.h"

#include <iostream>
#include <string>
#include <vector>

namespace {

  bool check(bool cond, const char* msg) {
    if (!cond) {
      std::cerr << "FAIL: " << msg << '\n';
    }
    return cond;
  }

  DesktopEntry entryWithCategories(std::string categories) {
    DesktopEntry entry;
    entry.name = "Example";
    entry.categories = std::move(categories);
    return entry;
  }

} // namespace

int main() {
  bool ok = true;

  const std::vector<DesktopEntry> entries = {
      entryWithCategories("Development;IDE;"),
      entryWithCategories("Audio;Player;"),
      entryWithCategories("Science;"),
      entryWithCategories(""),
  };

  const auto categories = availableLauncherAppCategories(entries);

  ok &= check(!categories.empty(), "available categories should include the provider default category");
  ok &= check(categories.front().id == LauncherAppCategories::All, "first category should be all");

  bool foundDevelopment = false;
  bool foundAudioVideo = false;
  bool foundEducation = false;
  bool foundNetwork = false;
  for (const auto& category : categories) {
    foundDevelopment = foundDevelopment || category.id == "Development";
    foundAudioVideo = foundAudioVideo || category.id == "AudioVideo";
    foundEducation = foundEducation || category.id == "Education";
    foundNetwork = foundNetwork || category.id == "Network";
  }

  ok &= check(foundDevelopment, "development category should be present");
  ok &= check(foundAudioVideo, "audio alias should expose AudioVideo category");
  ok &= check(foundEducation, "science alias should expose Education category");
  ok &= check(!foundNetwork, "missing categories should not be exposed");

  ok &= check(launcherAppEntryMatchesCategory(entries[0], "Development"), "development entry should match Development");
  ok &= check(launcherAppEntryMatchesCategory(entries[1], "AudioVideo"), "audio entry should match AudioVideo");
  ok &= check(launcherAppEntryMatchesCategory(entries[2], "Education"), "science entry should match Education");
  ok &= check(launcherAppEntryMatchesCategory(entries[3], LauncherAppCategories::All),
              "uncategorized entry should match All");
  ok &= check(!launcherAppEntryMatchesCategory(entries[3], "Development"),
              "uncategorized entry should not match Development");

  return ok ? 0 : 1;
}
```

- [ ] **Step 2: Rename the Meson test target**

In `meson.build`, change the test executable from `launcher_category_state_test` to `launcher_app_categories_test`, use `tests/launcher_app_categories_test.cpp` and `src/launcher/app_categories.cpp` as sources, and register `test('launcher_app_categories', launcher_app_categories_test)`. Delete `tests/launcher_category_state_test.cpp`.

- [ ] **Step 3: Run test to verify it fails before implementation**

Run:

```bash
meson compile -C build-debug launcher_app_categories_test
meson test -C build-debug launcher_app_categories --print-errorlogs
```

Expected: build fails because the target still references removed/renamed source wiring or because the implementation still includes old state APIs. This confirms the test/build target needs production changes.

### Task 2: Remove Provider-Owned Category Selection

**Files:**
- Modify: `src/launcher/launcher_provider.h`
- Modify: `src/launcher/app_provider.h`
- Modify: `src/launcher/app_provider.cpp`
- Delete: `src/launcher/launcher_category_state.h`
- Delete: `src/launcher/launcher_category_state.cpp`
- Modify: `meson.build`

- [ ] **Step 1: Update provider API**

In `src/launcher/launcher_provider.h`, remove:

```cpp
[[nodiscard]] virtual std::string_view selectedCategory() const { return {}; }
virtual void selectCategory(std::string_view /*category*/) {}
virtual void resetCategory() {}
```

Change `query` to:

```cpp
[[nodiscard]] virtual std::vector<LauncherResult> query(std::string_view text,
                                                        std::string_view category = {}) const = 0;
```

- [ ] **Step 2: Update non-category providers**

For `EmojiProvider`, `MathProvider`, and `WallpaperProvider`, update declarations and definitions to accept the category parameter and ignore it:

```cpp
std::vector<LauncherResult> query(std::string_view text, std::string_view /*category*/) const override;
```

- [ ] **Step 3: Make AppProvider stateless**

In `src/launcher/app_provider.h`, remove `selectedCategory()`, `selectCategory()`, `resetCategory()`, `ensureSelectedCategoryIsAvailable()`, and `m_selectedCategory`.

Change the declaration to:

```cpp
[[nodiscard]] std::vector<LauncherResult> query(std::string_view text,
                                                std::string_view category = {}) const override;
```

In `src/launcher/app_provider.cpp`, remove the selected-category helper implementations and use the query argument only for empty browse queries:

```cpp
std::vector<LauncherResult> AppProvider::query(std::string_view text, std::string_view category) const {
  refreshEntriesIfNeeded();
  const std::string normalizedText = StringUtils::toLower(text);
  const std::string_view pattern = normalizedText;

  auto buildResult = [&](const DesktopEntry& entry, double s) {
    LauncherResult result;
    result.id = entry.path;
    result.title = entry.name;
    result.subtitle = entry.genericName.empty() ? entry.comment : entry.genericName;
    result.iconName = entry.icon.empty() ? std::string(kDefaultAppIcon) : entry.icon;
    result.glyphName = "app-window";
    result.score = s;
    return result;
  };

  if (pattern.empty()) {
    std::vector<LauncherResult> results;
    results.reserve(m_entries.size());
    for (const auto& entry : m_entries) {
      if (!launcherAppEntryMatchesCategory(entry, category)) {
        continue;
      }
      results.push_back(buildResult(entry, 0));
    }
    return results;
  }
```

Keep the existing typed-search body after that block unchanged.

- [ ] **Step 4: Delete obsolete category state helper from build**

Remove `src/launcher/launcher_category_state.cpp` from `_noctalia_sources` and remove the source file/header from the repository.

- [ ] **Step 5: Run targeted compile**

Run:

```bash
meson compile -C build-debug launcher_app_categories_test
```

Expected: it should compile after Task 2 and before panel work, or fail only on remaining panel references to removed provider methods.

### Task 3: Move Selected Category State Into LauncherPanel

**Files:**
- Modify: `src/shell/launcher/launcher_panel.h`
- Modify: `src/shell/launcher/launcher_panel.cpp`
- Modify: `src/shell/launcher/launcher_panel_categories.cpp`

- [ ] **Step 1: Add panel-local state**

In `LauncherPanel`, add:

```cpp
std::string m_selectedCategory;
```

Do not include `launcher/app_categories.h` in launcher panel files.

- [ ] **Step 2: Clear category state on open and close**

In `LauncherPanel::onOpen`, replace provider reset loop with:

```cpp
m_selectedCategory.clear();
```

In `onClose`, also clear `m_selectedCategory`.

- [ ] **Step 3: Query providers with the panel category id**

In `LauncherPanel::onInputChanged`, compute the category argument only when browsing default providers:

```cpp
const std::string_view category = queryText.empty() ? std::string_view(m_selectedCategory) : std::string_view{};
```

Pass that to provider query calls:

```cpp
m_results = activeProvider->query(queryText, category);
auto results = provider->query(queryText, category);
```

- [ ] **Step 4: Inline category provider resolution without provider-specific code**

In `launcher_panel_categories.cpp`, remove `#include "launcher/launcher_category_state.h"`.

Implement `categoryProvider()` by scanning default-prefix providers with non-empty `availableCategories()` and returning one provider only:

```cpp
LauncherProvider* LauncherPanel::categoryProvider() const {
  LauncherProvider* candidate = nullptr;
  for (const auto& provider : m_providers) {
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
```

- [ ] **Step 5: Update category tab refresh**

In `updateCategoryTabs`, replace `LauncherCategoryState::resolveTabs` with local logic:

```cpp
LauncherProvider* provider = nullptr;
std::vector<LauncherCategory> categories;
bool visible = false;

if (categoryTabsEnabled() && m_query.empty()) {
  provider = categoryProvider();
  if (provider != nullptr) {
    categories = provider->availableCategories();
    visible = categories.size() > 1;
  }
}

if (!visible) {
  m_selectedCategory.clear();
}
```

When choosing the selected index, compare `m_selectedCategory` against `m_categories[i].id`; empty selection maps to index `0`.

- [ ] **Step 6: Update category selection**

In `selectCategory`, stop calling provider state methods:

```cpp
if (index == 0) {
  m_selectedCategory.clear();
} else {
  m_selectedCategory = m_categories[index].id;
}
onInputChanged(m_query);
```

- [ ] **Step 7: Verify launcher files do not contain provider-specific app code**

Run:

```bash
rg -n "AppProvider|appProvider|app_categories|LauncherAppCategories" src/shell/launcher
```

Expected: no matches.

### Task 4: Clean Tests And Verify

**Files:**
- Create: `tests/launcher_app_categories_test.cpp`
- Delete: `tests/launcher_category_state_test.cpp`
- Modify: `meson.build`

- [ ] **Step 1: Run category test**

Run:

```bash
meson compile -C build-debug launcher_app_categories_test
meson test -C build-debug launcher_app_categories --print-errorlogs
```

Expected: PASS.

- [ ] **Step 2: Search for removed API**

Run:

```bash
rg -n "launcher_category_state|selectedCategory|selectCategory|resetCategory" src tests meson.build
```

Expected: no matches except `LauncherPanel::selectCategory`, which is panel UI state and should remain.

- [ ] **Step 3: Build noctalia**

Run:

```bash
meson compile -C build-debug noctalia
```

Expected: build succeeds.

- [ ] **Step 4: Commit implementation**

Run:

```bash
git add src tests meson.build docs/superpowers/plans/2026-05-17-launcher-category-state-simplification.md
git commit -m "refactor(launcher): keep category state in panel"
```
