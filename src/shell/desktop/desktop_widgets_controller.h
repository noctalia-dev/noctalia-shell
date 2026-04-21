#pragma once

#include "config/config_service.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class DesktopWidgetsEditor;
class DesktopWidgetsHost;
class HttpClient;
class IpcService;
class MprisService;
class PipeWireSpectrum;
class RenderContext;
class TimeService;
class WaylandConnection;
class WeatherService;
struct KeyboardEvent;
struct PointerEvent;

struct DesktopWidgetsGridState {
  bool visible = true;
  std::int32_t cellSize = 16;
  std::int32_t majorInterval = 4;

  bool operator==(const DesktopWidgetsGridState&) const = default;
};

struct DesktopWidgetState {
  std::string id;
  std::string type = "clock";
  std::string outputName;
  float cx = 0.0f;
  float cy = 0.0f;
  float scale = 1.0f;
  float rotationRad = 0.0f;
  bool enabled = true;
  std::unordered_map<std::string, WidgetSettingValue> settings;

  bool operator==(const DesktopWidgetState&) const = default;
};

struct DesktopWidgetsSnapshot {
  std::int32_t schemaVersion = 1;
  DesktopWidgetsGridState grid;
  std::vector<DesktopWidgetState> widgets;

  bool operator==(const DesktopWidgetsSnapshot&) const = default;
};

class DesktopWidgetsController {
public:
  DesktopWidgetsController();
  ~DesktopWidgetsController();

  DesktopWidgetsController(const DesktopWidgetsController&) = delete;
  DesktopWidgetsController& operator=(const DesktopWidgetsController&) = delete;

  void initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                  PipeWireSpectrum* pipewireSpectrum, const WeatherService* weather, RenderContext* renderContext,
                  MprisService* mpris, HttpClient* httpClient);

  void registerIpc(IpcService& ipc);
  void onOutputChange();
  void onSecondTick();
  void requestLayout();
  void requestRedraw();

  void enterEdit();
  void exitEdit();
  void toggleEdit();

  [[nodiscard]] bool isEditing() const noexcept;
  [[nodiscard]] int watchFd() const noexcept { return m_inotifyFd; }
  void checkReload();
  bool onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);

private:
  void loadState();
  void saveState();
  void setupWatch();
  void applyVisibility();
  void normalizeSnapshot();
  [[nodiscard]] std::string stateFilePath() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TimeService* m_timeService = nullptr;
  RenderContext* m_renderContext = nullptr;

  DesktopWidgetsSnapshot m_snapshot;
  bool m_initialized = false;
  bool m_ownWritePending = false;
  int m_inotifyFd = -1;
  int m_watchWd = -1;
  std::unique_ptr<DesktopWidgetsHost> m_host;
  std::unique_ptr<DesktopWidgetsEditor> m_editor;
};
