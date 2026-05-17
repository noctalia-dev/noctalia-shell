#pragma once

#include "launcher/app_categories.h"
#include "launcher/launcher_provider.h"
#include "system/desktop_entry.h"

#include <cstdint>
#include <vector>

class WaylandConnection;

class AppProvider : public LauncherProvider {
public:
  explicit AppProvider(WaylandConnection* wayland = nullptr);

  [[nodiscard]] std::string_view prefix() const override { return ""; }
  [[nodiscard]] std::string_view name() const override { return "Applications"; }
  [[nodiscard]] bool trackUsage() const override { return true; }

  void initialize() override;

  [[nodiscard]] std::vector<LauncherResult> query(std::string_view text) const override;

  bool activate(const LauncherResult& result) override;

  [[nodiscard]] std::vector<LauncherCategory> availableCategories() const override;
  [[nodiscard]] std::string_view selectedCategory() const override { return m_selectedCategory; }
  void selectCategory(std::string_view category) override;
  void resetCategory() override;

private:
  void refreshEntriesIfNeeded() const;
  void ensureSelectedCategoryIsAvailable() const;

  WaylandConnection* m_wayland = nullptr;
  mutable std::vector<DesktopEntry> m_entries;
  mutable std::uint64_t m_entriesVersion = 0;
  mutable std::string m_selectedCategory{LauncherAppCategories::All};
};
