#pragma once

#include "shell/BarInstance.h"
#include "shell/WidgetFactory.h"

#include <functional>
#include <memory>
#include <unordered_map>
#include <vector>

class ConfigService;
class NotificationManager;
class TrayService;
class TimeService;
class WaylandConnection;
struct PointerEvent;
struct wl_output;
struct wl_surface;

class Bar {
public:
  using PanelRequestCallback = WidgetFactory::PanelRequestCallback;

  Bar();

  bool initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                  NotificationManager* notifications, TrayService* tray);
  void setPanelRequestCallback(PanelRequestCallback callback);
  void reload();
  void closeAllInstances();
  void onOutputChange();
  void onWorkspaceChange();
  void onPointerEvent(const PointerEvent& event);
  void redrawAll();
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
  std::unique_ptr<WidgetFactory> m_widgetFactory;
  std::vector<std::unique_ptr<BarInstance>> m_instances;

  PanelRequestCallback m_panelRequestCallback;

  // Surface → BarInstance mapping for pointer event routing
  std::unordered_map<wl_surface*, BarInstance*> m_surfaceMap;
  BarInstance* m_hoveredInstance = nullptr;
};
