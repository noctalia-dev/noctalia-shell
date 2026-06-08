#pragma once

#include "config/config_types.h"

#include <memory>

class Bar;
class ConfigService;
class Dock;
class DesktopWidgetsController;
class HttpClient;
class IpcService;
class LockScreen;
class BackgroundWidgetsEditor;
class LockscreenWidgetsHost;
class MprisService;
class PipeWireSpectrum;
class RenderContext;
class SharedTextureCache;
class SystemMonitorService;
class WaylandConnection;
class WeatherService;
struct KeyboardEvent;
struct PointerEvent;

using LockscreenWidgetsSnapshot = LockscreenWidgetsConfig;

class LockscreenWidgetsController {
public:
  LockscreenWidgetsController();
  ~LockscreenWidgetsController();

  LockscreenWidgetsController(const LockscreenWidgetsController&) = delete;
  LockscreenWidgetsController& operator=(const LockscreenWidgetsController&) = delete;

  void initialize(
      WaylandConnection& wayland, ConfigService* config, LockScreen& lockScreen, Bar& bar, Dock& dock,
      DesktopWidgetsController* desktopWidgets, PipeWireSpectrum* pipewireSpectrum, const WeatherService* weather,
      RenderContext* renderContext, MprisService* mpris, HttpClient* httpClient, SystemMonitorService* sysmon,
      SharedTextureCache* textureCache
  );

  void registerIpc(IpcService& ipc);
  void onLockStateChanged();
  void onOutputChange();
  void onSecondTick();
  void requestLayout();
  void requestRedraw();

  void enterEdit();
  void exitEdit();
  void toggleEdit();

  [[nodiscard]] bool isEditing() const noexcept;
  bool onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);

private:
  void loadSnapshotFromConfig();
  void saveSnapshotToConfig();
  void applyVisibility();
  void handleConfigReload();
  void normalizeSnapshot();

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  LockScreen* m_lockScreen = nullptr;
  Bar* m_bar = nullptr;
  Dock* m_dock = nullptr;
  DesktopWidgetsController* m_desktopWidgets = nullptr;
  RenderContext* m_renderContext = nullptr;

  LockscreenWidgetsSnapshot m_snapshot;
  bool m_initialized = false;
  std::unique_ptr<LockscreenWidgetsHost> m_host;
  std::unique_ptr<BackgroundWidgetsEditor> m_editor;
};
