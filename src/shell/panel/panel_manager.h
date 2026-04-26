#pragma once

#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "shell/panel/attached_panel_context.h"
#include "shell/panel/panel.h"
#include "ui/dialogs/layer_popup_host.h"
#include "wayland/layer_surface.h"
#include "wayland/surface.h"
#include "wayland/wayland_seat.h"

#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

class ConfigService;
class IpcService;
class Renderer;
class RenderContext;
class RectNode;
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

  // Optional: invoked from shell UI (e.g. control center) to spawn the standalone settings toplevel.
  void setOpenSettingsWindowCallback(std::function<void()> callback);
  void openSettingsWindow();
  void setAttachedPanelParentResolver(std::function<std::optional<AttachedPanelParentContext>(wl_output*)> resolver);
  void setAttachedPanelGeometryCallback(std::function<void(wl_output*, std::optional<AttachedPanelGeometry>)> callback);

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
  [[nodiscard]] std::optional<LayerPopupParentContext> popupParentContextForSurface(wl_surface* surface) const noexcept;
  [[nodiscard]] std::optional<LayerPopupParentContext> fallbackPopupParentContext() const noexcept;

  void refresh();
  void requestUpdateOnly();
  void requestLayout();
  // Requests a redraw on the active panel surface without re-running panel
  // update/layout. Used for reactive palette restyling.
  void requestRedraw();
  void close();
  void beginAttachedPopup(wl_surface* surface);
  void endAttachedPopup(wl_surface* surface);

  void registerIpc(IpcService& ipc);

private:
  enum class AttachedRevealDirection : std::uint8_t {
    Down,
    Up,
    Right,
    Left,
  };

  static PanelManager* s_instance;

  void buildScene(std::uint32_t width, std::uint32_t height);
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void destroyPanel();
  void applyAttachedReveal(float progress);
  void publishAttachedPanelGeometry(float revealProgress);

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  std::function<void()> m_openSettingsWindow;
  std::function<std::optional<AttachedPanelParentContext>(wl_output*)> m_attachedPanelParentResolver;
  std::function<void(wl_output*, std::optional<AttachedPanelGeometry>)> m_attachedPanelGeometryCallback;

  std::unique_ptr<Surface> m_surface;
  LayerSurface* m_layerSurface = nullptr;
  // m_sceneRoot must be destroyed before m_animations — ~Node() calls cancelForOwner().
  // Also m_panels (which own their own Nodes parented under m_sceneRoot) must be destroyed
  // before m_animations for the same reason.
  AnimationManager m_animations;
  std::unique_ptr<Node> m_sceneRoot;
  Node* m_bgNode = nullptr;
  Node* m_contentNode = nullptr;
  Node* m_attachedRevealClipNode = nullptr;
  Node* m_attachedRevealContentNode = nullptr;
  RectNode* m_panelShadowNode = nullptr;
  RectNode* m_panelContactShadowNode = nullptr;
  InputDispatcher m_inputDispatcher;

  std::unordered_map<std::string, std::unique_ptr<Panel>> m_panels;
  Panel* m_activePanel = nullptr;
  std::string m_activePanelId;
  std::string m_pendingOpenContext;

  wl_output* m_output = nullptr;
  wl_surface* m_wlSurface = nullptr;
  float m_contentWidth = 0.0f;
  float m_contentHeight = 0.0f;
  std::int32_t m_panelInsetX = 0;
  std::int32_t m_panelInsetY = 0;
  std::uint32_t m_panelVisualWidth = 0;
  std::uint32_t m_panelVisualHeight = 0;
  float m_attachedBackgroundOpacity = 1.0f;
  float m_attachedRevealProgress = 1.0f;
  AttachedRevealDirection m_attachedRevealDirection = AttachedRevealDirection::Down;
  std::optional<AttachedPanelGeometry> m_attachedPanelGeometry;
  bool m_pointerInside = false;
  bool m_inTransition = false;
  bool m_closing = false;
  bool m_attachedToBar = false;
  std::size_t m_attachedPopupCount = 0;
  std::uint64_t m_destroyGeneration = 0; // invalidates stale deferred destroyPanel calls
};
