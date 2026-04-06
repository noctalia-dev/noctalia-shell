#pragma once

#include "render/core/texture_manager.h"
#include "shell/wallpaper/wallpaper_instance.h"

#include <EGL/egl.h>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class ConfigService;
class StateService;
class WaylandConnection;
struct WaylandOutput;

class Wallpaper {
public:
  Wallpaper();
  ~Wallpaper();

  bool initialize(WaylandConnection& wayland, ConfigService* config, StateService* state);
  void onOutputChange();
  void onStateChange();
  [[nodiscard]] bool hasInstances() const noexcept;

private:
  void reload();
  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void loadWallpaper(WallpaperInstance& instance, const std::string& path);
  void startTransition(WallpaperInstance& instance);
  void updateRendererState(WallpaperInstance& instance);

  // Shared texture cache — textures are uploaded once and reused across all
  // instances that share the same wallpaper path (via EGL context sharing).
  TextureHandle acquireTexture(const std::string& path);
  void releaseTexture(TextureHandle& handle, const std::string& path);
  void releaseInstanceTextures(WallpaperInstance& inst);
  void makeAnyContextCurrent();

  struct CachedTexture {
    TextureHandle handle;
    int refCount = 0;
  };

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  StateService* m_state = nullptr;
  std::vector<std::unique_ptr<WallpaperInstance>> m_instances;

  // Shared GL resources — must be declared after m_instances so it is
  // destroyed first (while EGL contexts from m_instances are still alive).
  EGLContext m_shareContext = EGL_NO_CONTEXT;
  std::unordered_map<std::string, CachedTexture> m_textureCache;
  TextureManager m_sharedTexManager;
};
