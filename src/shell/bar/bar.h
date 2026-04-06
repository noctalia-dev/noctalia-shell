#pragma once

#include "shell/bar/bar_instance.h"
#include "shell/widget/widget_factory.h"

#include <memory>
#include <unordered_map>
#include <vector>

class ConfigService;
class NotificationManager;
class PipeWireService;
class RenderContext;
class UPowerService;
class TrayService;
class TimeService;
class WaylandConnection;
struct PointerEvent;
struct wl_surface;

class Bar {
public:
  Bar();

  bool initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                  NotificationManager* notifications, TrayService* tray, PipeWireService* audio,
                  UPowerService* upower, RenderContext* renderContext);
  void reload();
  void closeAllInstances();
  void onOutputChange();
  void onWorkspaceChange();
  bool onPointerEvent(const PointerEvent& event);
  [[nodiscard]] bool isRunning() const noexcept;

private:
  void syncInstances();
  void createInstance(const WaylandOutput& output, const BarConfig& barConfig);
  void destroyInstance(std::uint32_t outputName);
  void populateWidgets(BarInstance& instance);
  void buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height);
  void updateWidgets(BarInstance& instance);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TimeService* m_time = nullptr;
  NotificationManager* m_notifications = nullptr;
  TrayService* m_tray = nullptr;
  PipeWireService* m_audio = nullptr;
  UPowerService* m_upower = nullptr;
  RenderContext* m_renderContext = nullptr;
  std::unique_ptr<WidgetFactory> m_widgetFactory;
  std::vector<std::unique_ptr<BarInstance>> m_instances;

  // Surface → BarInstance mapping for pointer event routing
  std::unordered_map<wl_surface*, BarInstance*> m_surfaceMap;
  BarInstance* m_hoveredInstance = nullptr;
};
