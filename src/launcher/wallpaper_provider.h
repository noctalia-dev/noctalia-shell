#pragma once

#include "launcher/launcher_provider.h"

class ConfigService;
class WaylandConnection;

class WallpaperProvider : public LauncherProvider {
public:
  WallpaperProvider(ConfigService* config, WaylandConnection* wayland);

  [[nodiscard]] std::string_view prefix() const override { return "/wall"; }
  [[nodiscard]] std::string_view id() const override { return "Wallpaper"; }
  [[nodiscard]] std::string displayName() const override;
  [[nodiscard]] std::string_view defaultGlyphName() const override { return "wallpaper-selector"; }
  [[nodiscard]] bool trackUsage() const override { return true; }

  [[nodiscard]] std::vector<LauncherResult> query(std::string_view text) const override;

  bool activate(const LauncherResult& result) override;

private:
  ConfigService* m_config = nullptr;
  WaylandConnection* m_wayland = nullptr;
};
