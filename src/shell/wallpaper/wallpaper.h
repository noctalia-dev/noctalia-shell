#pragma once

#include "core/timer_manager.h"
#include "config/config_types.h"
#include "shell/wallpaper/wallpaper_instance.h"
#include "ui/signal.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

class ConfigService;
class IpcService;
class ProjectMRenderer;
class RenderContext;
class SharedTextureCache;
class VisualizerService;
class WaylandConnection;
struct WaylandOutput;

class Wallpaper {
public:
  Wallpaper();
  ~Wallpaper();

  bool initialize(
      WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext, SharedTextureCache* textureCache
  );

  // Optional live-paper plumbing. Both pointers are non-owning. Pass nulls
  // to keep the static-image-only behaviour.
  void setVisualizer(ProjectMRenderer* renderer, VisualizerService* service);

  void onOutputChange();
  void onStateChange();
  void onSecondTick();
  void onGpuResourcesInvalidated();
  void registerIpc(IpcService& ipc);

  [[nodiscard]] TextureHandle currentTexture() const;

private:
  void reload();
  void syncInstances();
  void resetAutomationState();
  void runAutomation(std::int64_t minuteStamp);
  [[nodiscard]] bool switchToRandomWallpaper(std::optional<std::string_view> connector = std::nullopt);
  void createInstance(const WaylandOutput& output);
  [[nodiscard]] TextureHandle acquireTexture(const std::string& path);
  void releaseTexture(TextureHandle& handle, const std::string& path);
  void loadWallpaper(WallpaperInstance& instance, const std::string& path);
  void startTransition(WallpaperInstance& instance);
  void updateRendererState(WallpaperInstance& instance);
  void releaseInstanceTextures(WallpaperInstance& inst);

  // Live-paper drive: a global timer that renders one libprojectM frame and
  // then asks each wallpaper surface to redraw. Honors fps from
  // [wallpaper.live_paper]; reschedules on config change.
  [[nodiscard]] bool livePaperActive() const noexcept;
  void syncVisualizerTimer();
  void onVisualizerTick();

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  SharedTextureCache* m_textureCache = nullptr;
  ProjectMRenderer* m_visualizer = nullptr;
  VisualizerService* m_visualizerService = nullptr;
  bool m_wallpaperEnabled = false;
  WallpaperConfig m_lastWallpaperConfig{};
  std::int64_t m_lastAutomationMinuteStamp = -1;
  std::int64_t m_lastAutomationSwitchMinute = -1;
  Signal<>::ScopedConnection m_paletteConn;
  std::vector<std::unique_ptr<WallpaperInstance>> m_instances;

  Timer m_visualizerTimer;
  int m_visualizerTickFps = 0; // last fps we scheduled for
};
