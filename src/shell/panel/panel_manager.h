#pragma once

#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "shell/panel/panel.h"
#include "wayland/layer_surface.h"
#include "wayland/wayland_seat.h"

#include <memory>
#include <string>
#include <string_view>
#include <unordered_map>

class ConfigService;
class RenderContext;
class WaylandConnection;
struct PointerEvent;
struct wl_output;
struct wl_surface;

class PanelManager {
public:
  PanelManager();
  ~PanelManager();

  PanelManager(const PanelManager&) = delete;
  PanelManager& operator=(const PanelManager&) = delete;

  static PanelManager& instance();

  void initialize(WaylandConnection& wayland, ConfigService* config, RenderContext* renderContext);

  void registerPanel(const std::string& id, std::unique_ptr<Panel> content);

  void openPanel(const std::string& panelId, wl_output* output, float anchorX, float anchorY,
                 std::string_view context = {});
  void closePanel();
  void togglePanel(const std::string& panelId, wl_output* output, float anchorX, float anchorY,
                   std::string_view context = {});
  // IPC-friendly overload: asks WaylandConnection for preferred interactive output.
  void togglePanel(const std::string& panelId);

  bool onPointerEvent(const PointerEvent& event);
  void onKeyboardEvent(const KeyboardEvent& event);

  [[nodiscard]] bool isOpen() const noexcept;
  [[nodiscard]] const std::string& activePanelId() const noexcept;

  void refresh();
  // Requests a redraw on the active panel surface without re-running panel
  // update/layout. Used for reactive palette restyling.
  void requestRedraw();
  void close();

private:
  static PanelManager* s_instance;

  void buildScene(std::uint32_t width, std::uint32_t height);
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void destroyPanel();

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;

  std::unique_ptr<LayerSurface> m_surface;
  std::unique_ptr<Node> m_sceneRoot;
  Node* m_bgNode = nullptr;
  Node* m_contentNode = nullptr;
  AnimationManager m_animations;
  InputDispatcher m_inputDispatcher;

  std::unordered_map<std::string, std::unique_ptr<Panel>> m_panels;
  Panel* m_activePanel = nullptr;
  std::string m_activePanelId;
  std::string m_pendingOpenContext;

  wl_surface* m_wlSurface = nullptr;
  float m_contentWidth = 0.0f;
  float m_contentHeight = 0.0f;
  bool m_pointerInside = false;
  bool m_inTransition = false;
  bool m_closing = false;
  std::uint64_t m_destroyGeneration = 0; // invalidates stale deferred destroyPanel calls
};
