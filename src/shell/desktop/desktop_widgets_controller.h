#pragma once

#include "config/config_service.h"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class DesktopWidgetsEditor;
class DesktopWidgetsHost;
class IpcService;
class PipeWireSpectrum;
class RenderContext;
class TimeService;
class WaylandConnection;
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
                  PipeWireSpectrum* pipewireSpectrum, RenderContext* renderContext);

  void registerIpc(IpcService& ipc);
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
  void loadState();
  void saveState() const;
  void applyVisibility();
  void normalizeSnapshot();
  [[nodiscard]] std::string stateFilePath() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TimeService* m_timeService = nullptr;
  RenderContext* m_renderContext = nullptr;

  DesktopWidgetsSnapshot m_snapshot;
  bool m_initialized = false;
  std::unique_ptr<DesktopWidgetsHost> m_host;
  std::unique_ptr<DesktopWidgetsEditor> m_editor;
};
