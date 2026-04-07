#pragma once

#include "launcher/launcher_provider.h"
#include "system/desktop_entry.h"
#include "system/icon_resolver.h"

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

private:
  void refreshEntriesIfNeeded() const;

  WaylandConnection* m_wayland = nullptr;
  mutable std::vector<DesktopEntry> m_entries;
  mutable std::uint64_t m_entriesVersion = 0;
  mutable IconResolver m_iconResolver;
};
