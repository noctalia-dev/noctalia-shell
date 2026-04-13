#pragma once

#include "render/core/texture_manager.h"
#include "shell/wallpaper/wallpaper_instance.h"

#include <EGL/egl.h>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class ConfigService;
class WaylandConnection;
struct WaylandOutput;

class Wallpaper {
public:
  Wallpaper();
  ~Wallpaper();

  bool initialize(WaylandConnection& wayland, ConfigService* config);
  void onOutputChange();
  void onStateChange();
  [[nodiscard]] bool hasInstances() const noexcept;

  // Shared texture cache — public so Overview can share textures without
  // duplicating VRAM. Caller must ensure a context is current or let
  // acquireTexture handle it internally.
  [[nodiscard]] EGLContext shareContext() const noexcept { return m_shareContext; }
  TextureHandle acquireTexture(const std::string& path);
  void releaseTexture(TextureHandle& handle, const std::string& path);

private:
  void reload();
  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void loadWallpaper(WallpaperInstance& instance, const std::string& path);
  void startTransition(WallpaperInstance& instance);
  void updateRendererState(WallpaperInstance& instance);

  void releaseInstanceTextures(WallpaperInstance& inst);
  void makeAnyContextCurrent();
  void refreshShareContext();

  struct CachedTexture {
    TextureHandle handle;
    int refCount = 0;
  };

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  std::vector<std::unique_ptr<WallpaperInstance>> m_instances;

  // Shared GL resources — must be declared after m_instances so it is
  // destroyed first (while EGL contexts from m_instances are still alive).
  EGLContext m_shareContext = EGL_NO_CONTEXT;
  std::unordered_map<std::string, CachedTexture> m_textureCache;
  TextureManager m_sharedTexManager;
};
