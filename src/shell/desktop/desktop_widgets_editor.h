#pragma once

#include "render/scene/node.h"
#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "shell/desktop/desktop_widget_factory.h"
#include "shell/desktop/desktop_widgets_controller.h"
#include "wayland/layer_surface.h"

#include <functional>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

class Box;
class Button;
class ConfigService;
class InputArea;
class PipeWireSpectrum;
class RenderContext;
class Select;
class TimeService;
class WaylandConnection;
struct KeyboardEvent;
struct PointerEvent;
struct WaylandOutput;
struct wl_output;
struct wl_surface;

class DesktopWidgetsEditor {
public:
  DesktopWidgetsEditor() = default;

  void initialize(WaylandConnection& wayland, ConfigService* config, TimeService* timeService,
                  PipeWireSpectrum* pipewireSpectrum, RenderContext* renderContext);
  void setExitRequestedCallback(std::function<void()> callback);

  void open(const DesktopWidgetsSnapshot& snapshot);
  [[nodiscard]] DesktopWidgetsSnapshot close();
  [[nodiscard]] bool isOpen() const noexcept;

  bool onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);
  void onOutputChange();
  void onSecondTick();
  void requestLayout();
  void requestRedraw();

private:
  enum class DragMode : std::uint8_t {
    None,
    Move,
    Scale,
    Rotate,
  };

  struct EditorWidgetView {
    std::unique_ptr<DesktopWidget> widget;
    Node* transformNode = nullptr;
    InputArea* bodyArea = nullptr;
    float intrinsicWidth = 0.0f;
    float intrinsicHeight = 0.0f;
  };

  struct OverlaySurface {
    std::string outputName;
    wl_output* output = nullptr;
    std::unique_ptr<LayerSurface> surface;
    AnimationManager animations;
    InputDispatcher inputDispatcher;
    std::unique_ptr<Node> sceneRoot;
    bool sceneRebuildRequested = true;
    std::unordered_map<std::string, EditorWidgetView> views;
    Box* selectionBorder = nullptr;
    Box* rotationRing = nullptr;
    Box* scaleHandle = nullptr;
    InputArea* rotateArea = nullptr;
    InputArea* scaleArea = nullptr;
    bool pointerInside = false;
  };

  struct DragState {
    DragMode mode = DragMode::None;
    std::string widgetId;
    float startSceneX = 0.0f;
    float startSceneY = 0.0f;
    DesktopWidgetState initialState;
    float intrinsicWidth = 0.0f;
    float intrinsicHeight = 0.0f;
    bool rebuildOnFinish = false;
  };

  void syncSurfaces();
  void createSurface(const WaylandOutput& output);
  void rebuildScene(OverlaySurface& surface);
  void prepareFrame(OverlaySurface& surface, bool needsUpdate, bool needsLayout);
  void updateViewTransforms();
  void updateSelectionVisuals(OverlaySurface& surface);
  void addWidget(const std::string& outputName, const std::string& type);
  void removeSelectedWidget();
  void requestExit();
  void startDrag(DragMode mode, const std::string& widgetId, float intrinsicWidth, float intrinsicHeight, bool rebuildOnFinish);
  void updateDrag();
  void finishDrag();
  [[nodiscard]] OverlaySurface* findSurface(wl_surface* surface);
  [[nodiscard]] DesktopWidgetState* findWidgetState(const std::string& id);
  [[nodiscard]] const DesktopWidgetState* findWidgetState(const std::string& id) const;
  [[nodiscard]] std::string effectiveOutputName(const DesktopWidgetState& state) const;
  [[nodiscard]] bool shouldSnap() const;

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  TimeService* m_timeService = nullptr;
  RenderContext* m_renderContext = nullptr;
  std::unique_ptr<DesktopWidgetFactory> m_factory;
  std::string m_addWidgetType = "clock";
  std::function<void()> m_exitRequestedCallback;
  DesktopWidgetsSnapshot m_snapshot;
  std::vector<std::unique_ptr<OverlaySurface>> m_surfaces;
  std::string m_selectedWidgetId;
  DragState m_drag;
  bool m_open = false;
  bool m_shiftHeld = false;
  float m_currentEventSceneX = 0.0f;
  float m_currentEventSceneY = 0.0f;
};
