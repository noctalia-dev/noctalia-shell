#pragma once

#include "config/config_types.h"
#include "render/animation/animation_manager.h"
#include "render/scene/node.h"
#include "shell/desktop/desktop_widget_factory.h"

#include <memory>
#include <string>
#include <vector>

class ConfigService;
class HttpClient;
class LockScreen;
class LockSurface;
class MprisService;
class PipeWireSpectrum;
class RenderContext;
class SystemMonitorService;
class WaylandConnection;
class WeatherService;

using LockscreenWidgetsSnapshot = LockscreenWidgetsConfig;

class LockscreenWidgetsHost {
public:
  LockscreenWidgetsHost() = default;

  void initialize(
      WaylandConnection& wayland, ConfigService* config, PipeWireSpectrum* pipewireSpectrum,
      const WeatherService* weather, RenderContext* renderContext, MprisService* mpris, HttpClient* httpClient,
      SystemMonitorService* sysmon
  );
  void show(const LockscreenWidgetsSnapshot& snapshot, LockScreen& lockScreen);
  void hide();
  void rebuild(const LockscreenWidgetsSnapshot& snapshot, LockScreen& lockScreen);
  void onOutputChange(LockScreen& lockScreen);
  void onSecondTick();
  void prepareFrame(LockSurface& surface, bool needsUpdate, bool needsLayout);

private:
  struct WidgetInstance {
    DesktopWidgetState state;
    LockSurface* surface = nullptr;
    AnimationManager animations;
    Node* transformNode = nullptr;
    std::unique_ptr<DesktopWidget> widget;
    float intrinsicWidth = 0.0f;
    float intrinsicHeight = 0.0f;
  };

  void syncSurfaces(LockScreen& lockScreen);
  void createInstance(const DesktopWidgetState& state, LockSurface& surface, const WaylandOutput& output);
  void attachToSurface(WidgetInstance& instance);
  void detachFromSurface(WidgetInstance& instance);
  void updateBuiltinClockVisibility(LockScreen& lockScreen);
  [[nodiscard]] WidgetInstance* findInstance(const std::string& id);
  [[nodiscard]] LockSurface* findSurfaceForOutput(LockScreen& lockScreen, const std::string& outputKey) const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  std::unique_ptr<DesktopWidgetFactory> m_factory;
  LockscreenWidgetsSnapshot m_snapshot;
  bool m_visible = false;
  std::vector<std::unique_ptr<WidgetInstance>> m_instances;
};
