#pragma once

#include "core/timer_manager.h"
#include "shell/backdrop/backdrop_instance.h"

#include <memory>
#include <vector>

class ConfigService;
class GlSharedContext;
class SharedTextureCache;
class WaylandConnection;
struct WaylandOutput;

class Backdrop {
public:
  Backdrop();
  ~Backdrop();

  bool initialize(WaylandConnection& wayland, ConfigService* config, SharedTextureCache* textureCache,
                  GlSharedContext* sharedGl, bool active);
  void onOutputChange();
  void onFontChanged();
  void onStateChange();
  void onThemeChanged();
  void requestLayout();
  void setActive(bool active);
  [[nodiscard]] bool isActive() const noexcept { return m_active; }

private:
  [[nodiscard]] bool isSupportedForCurrentCompositor() const;
  [[nodiscard]] bool shouldBeActiveForCurrentCompositorState() const;
  [[nodiscard]] bool shouldKeepLoadedWhileInactive() const;
  [[nodiscard]] bool shouldRenderSurfaces() const;
  [[nodiscard]] bool shouldHaveInstances() const;
  void reload();
  void destroyInstances();
  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void ensureInstanceWallpaperLoaded(BackdropInstance& inst);
  void loadWallpaper(BackdropInstance& inst, const std::string& path);
  void updateRendererState(BackdropInstance& inst);
  void releaseInstanceTexture(BackdropInstance& inst, bool clearPath = true);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  SharedTextureCache* m_textureCache = nullptr;
  GlSharedContext* m_sharedGl = nullptr;
  std::vector<std::unique_ptr<BackdropInstance>> m_instances;
  bool m_active = false;
  Timer m_destroyDelayTimer;
};
