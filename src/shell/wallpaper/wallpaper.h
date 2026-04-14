#pragma once

#include "shell/wallpaper/wallpaper_instance.h"

#include <memory>
#include <string>
#include <vector>

class ConfigService;
class GlSharedContext;
class SharedTextureCache;
class WaylandConnection;
struct WaylandOutput;

class Wallpaper {
public:
  Wallpaper();
  ~Wallpaper();

  bool initialize(WaylandConnection& wayland, ConfigService* config, GlSharedContext* sharedGl,
                  SharedTextureCache* textureCache);
  void onOutputChange();
  void onStateChange();

private:
  void reload();
  void syncInstances();
  void createInstance(const WaylandOutput& output);
  void loadWallpaper(WallpaperInstance& instance, const std::string& path);
  void startTransition(WallpaperInstance& instance);
  void updateRendererState(WallpaperInstance& instance);
  void releaseInstanceTextures(WallpaperInstance& inst);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  GlSharedContext* m_sharedGl = nullptr;
  SharedTextureCache* m_textureCache = nullptr;
  std::vector<std::unique_ptr<WallpaperInstance>> m_instances;
};
