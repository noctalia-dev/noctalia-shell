#pragma once

#include "shell/overview/overview_instance.h"

#include <memory>
#include <vector>

class ConfigService;
class StateService;
class Wallpaper;
class WaylandConnection;
struct WaylandOutput;

class Overview {
public:
  Overview();
  ~Overview();

  bool initialize(WaylandConnection& wayland, ConfigService* config, StateService* state, Wallpaper* wallpaper);
  void onOutputChange();
  void onStateChange();
  void onThemeChanged();

private:
  void reload();
  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void loadWallpaper(OverviewInstance& inst, const std::string& path);
  void updateRendererState(OverviewInstance& inst);
  void releaseInstanceTexture(OverviewInstance& inst);

  WaylandConnection* m_wayland  = nullptr;
  ConfigService*     m_config   = nullptr;
  StateService*      m_state    = nullptr;
  Wallpaper*         m_wallpaper = nullptr;
  std::vector<std::unique_ptr<OverviewInstance>> m_instances;
};
