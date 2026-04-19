#pragma once

#include "shell/overview/overview_instance.h"

#include <memory>
#include <vector>

class ConfigService;
class GlSharedContext;
class SharedTextureCache;
class WaylandConnection;
struct WaylandOutput;

class Overview {
public:
  Overview();
  ~Overview();

  bool initialize(WaylandConnection& wayland, ConfigService* config, SharedTextureCache* textureCache,
                  GlSharedContext* sharedGl);
  void onOutputChange();
  void onFontChanged();
  void onStateChange();
  void onThemeChanged();
  void requestLayout();
  void setActive(bool active);
  [[nodiscard]] bool isActive() const noexcept { return m_active; }

private:
  void reload();
  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void loadWallpaper(OverviewInstance& inst, const std::string& path);
  void updateRendererState(OverviewInstance& inst);
  void releaseInstanceTexture(OverviewInstance& inst, bool clearPath = true);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  SharedTextureCache* m_textureCache = nullptr;
  GlSharedContext* m_sharedGl = nullptr;
  std::vector<std::unique_ptr<OverviewInstance>> m_instances;
  bool m_active = true;
};
