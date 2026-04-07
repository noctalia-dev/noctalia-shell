#pragma once

#include "launcher/desktop_entry.h"
#include "launcher/icon_resolver.h"
#include "launcher/launcher_provider.h"

#include <vector>

class WaylandConnection;

class AppProvider : public LauncherProvider {
public:
  explicit AppProvider(WaylandConnection* wayland = nullptr);

  [[nodiscard]] std::string_view prefix() const override { return ""; }
  [[nodiscard]] std::string_view name() const override { return "Applications"; }

  void initialize() override;

  [[nodiscard]] std::vector<LauncherResult> query(std::string_view text) const override;

  bool activate(const LauncherResult& result) override;

private:
  WaylandConnection* m_wayland = nullptr;
  std::vector<DesktopEntry> m_entries;
  mutable IconResolver m_iconResolver;
};
