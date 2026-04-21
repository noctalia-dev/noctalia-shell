#pragma once

#include "shell/bar/bar_instance.h"
#include "shell/bar/widget_factory.h"
#include "ui/dialogs/layer_popup_host.h"

#include <functional>
#include <memory>
#include <optional>
#include <unordered_map>
#include <vector>

class ConfigService;
class HttpClient;
class IdleInhibitor;
class IpcService;
class MprisService;
class BluetoothService;
class BrightnessService;
class NetworkService;
class NotificationManager;
class PipeWireService;
class PipeWireSpectrum;
class PowerProfilesService;
class RenderContext;
class SystemMonitorService;
class UPowerService;
class TrayService;
class TimeService;
class WaylandConnection;
class NightLightManager;
class WeatherService;
namespace noctalia::theme {
  class ThemeService;
}
struct PointerEvent;
struct wl_surface;

class Bar {
public:
  Bar();

  bool initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                  NotificationManager* notifications, TrayService* tray, PipeWireService* audio, UPowerService* upower,
                  SystemMonitorService* sysmon, PowerProfilesService* powerProfiles, NetworkService* network,
                  IdleInhibitor* idleInhibitor, MprisService* mpris, PipeWireSpectrum* audioSpectrum,
                  HttpClient* httpClient, WeatherService* weatherService, RenderContext* renderContext,
                  NightLightManager* nightLight, noctalia::theme::ThemeService* themeService,
                  BluetoothService* bluetooth, BrightnessService* brightness);
  void reload();
  void closeAllInstances();
  void show();
  void hide();
  [[nodiscard]] bool isVisible() const noexcept { return !m_forceHidden; }
  void onOutputChange();
  void onSecondTick();
  void refresh();
  void requestLayout();
  void setAutoHideSuppressionCallback(std::function<bool()> callback);
  // Requests a redraw on every bar surface without re-running widget update/layout.
  // Intended for reactive restyling (palette changes) where the scene graph has
  // already been mutated in place and only a repaint is needed.
  void requestRedraw();
  bool onPointerEvent(const PointerEvent& event);
  [[nodiscard]] bool isRunning() const noexcept;
  [[nodiscard]] std::optional<LayerPopupParentContext> popupParentContextForSurface(wl_surface* surface) const noexcept;
  [[nodiscard]] std::optional<LayerPopupParentContext> preferredPopupParentContext(wl_output* output) const noexcept;
  void beginAttachedPopup(wl_surface* surface);
  void endAttachedPopup(wl_surface* surface);

  void registerIpc(IpcService& ipc);

private:
  static void tickWidgets(std::vector<std::unique_ptr<Widget>>& widgets, float deltaMs);
  [[nodiscard]] static bool widgetsNeedFrameTick(const std::vector<std::unique_ptr<Widget>>& widgets);
  [[nodiscard]] static bool instanceNeedsFrameTick(const BarInstance& instance);
  void syncInstances();
  void createInstance(const WaylandOutput& output, const BarConfig& barConfig);
  void destroyInstance(std::uint32_t outputName);
  void populateWidgets(BarInstance& instance);
  void buildScene(BarInstance& instance, std::uint32_t width, std::uint32_t height);
  void prepareFrame(BarInstance& instance, bool needsUpdate, bool needsLayout);
  void updateWidgets(BarInstance& instance);
  void applyBarCompositorBlur(BarInstance& instance) const;
  void syncBarSlideLayerTransform(BarInstance& instance) const;
  void startHideFadeOut(BarInstance& instance);
  static void applyBackgroundPalette(BarInstance& instance);
  [[nodiscard]] BarInstance* instanceForSurface(wl_surface* surface) const noexcept;
  [[nodiscard]] BarInstance* instanceForOutput(wl_output* output) const noexcept;

  bool m_forceHidden = false;
  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TimeService* m_time = nullptr;
  NotificationManager* m_notifications = nullptr;
  TrayService* m_tray = nullptr;
  PipeWireService* m_audio = nullptr;
  UPowerService* m_upower = nullptr;
  SystemMonitorService* m_sysmon = nullptr;
  PowerProfilesService* m_powerProfiles = nullptr;
  NetworkService* m_network = nullptr;
  IdleInhibitor* m_idleInhibitor = nullptr;
  MprisService* m_mpris = nullptr;
  PipeWireSpectrum* m_audioSpectrum = nullptr;
  HttpClient* m_httpClient = nullptr;
  WeatherService* m_weatherService = nullptr;
  RenderContext* m_renderContext = nullptr;
  NightLightManager* m_nightLight = nullptr;
  noctalia::theme::ThemeService* m_themeService = nullptr;
  BluetoothService* m_bluetooth = nullptr;
  BrightnessService* m_brightness = nullptr;
  std::unique_ptr<WidgetFactory> m_widgetFactory;
  std::vector<std::unique_ptr<BarInstance>> m_instances;

  // Snapshot of the config fields the bar depends on. Used to skip reloads
  // triggered by unrelated config changes (theme, weather, idle, etc.).
  std::vector<BarConfig> m_lastBars;
  std::unordered_map<std::string, WidgetConfig> m_lastWidgets;

  // Surface → BarInstance mapping for pointer event routing
  std::unordered_map<wl_surface*, BarInstance*> m_surfaceMap;
  BarInstance* m_hoveredInstance = nullptr;
  std::function<bool()> m_autoHideSuppressionCallback;
};
