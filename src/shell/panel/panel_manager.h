#pragma once

#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "shell/panel/attached_panel_context.h"
#include "shell/panel/panel.h"
#include "shell/panel/panel_click_shield.h"
#include "shell/panel/panel_focus_grab.h"
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
class ContextMenuPopup;
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
  void setAttachedPanelGeometryCallback(std::function<void(wl_output*, std::optional<AttachedPanelGeometry>)> callback);
  // Callback to query the bar surface rects on a given output, in output-local
  // coordinates. The click shield's input region excludes these rects so
  // clicks on bar widgets keep flowing to the bar while a panel is open.
  void setClickShieldExcludeRectsProvider(std::function<std::vector<InputRect>(wl_output*)> provider);
  // Callback returning every bar wl_surface. Used to seed the Hyprland focus
  // grab whitelist so bar widgets keep receiving clicks while a panel is open.
  void setFocusGrabBarSurfacesProvider(std::function<std::vector<wl_surface*>()> provider);

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
  [[nodiscard]] bool isAttachedOpen() const noexcept;
  [[nodiscard]] const std::string& activePanelId() const noexcept;
  [[nodiscard]] std::optional<LayerPopupParentContext> popupParentContextForSurface(wl_surface* surface) const noexcept;
  [[nodiscard]] std::optional<LayerPopupParentContext> fallbackPopupParentContext() const noexcept;

  [[nodiscard]] RenderContext* renderContext() const noexcept { return m_renderContext; }
  [[nodiscard]] WaylandConnection* wayland() const noexcept { return m_wayland; }

  void setActivePopup(ContextMenuPopup* popup);
  void clearActivePopup();

  void refresh();
  // Reacts to a ConfigService reload while a panel is open: re-pulls the host bar's
  // per-panel-relevant config (currently backgroundOpacity, attached panels only) and
  // re-applies the compositor blur region (which depends on shell.panel.background_blur,
  // affects both attached and layer-shell panels). No-op when no panel is open.
  void onConfigReloaded();
  void onIconThemeChanged();
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
  static PanelManager* s_instance;

  void buildScene(std::uint32_t width, std::uint32_t height);
  void prepareFrame(bool needsUpdate, bool needsLayout);
  void destroyPanel();
  // Called BEFORE the panel surface commits so shields sit below the panel
  // within the layer-shell layer. No-op when the focus-grab path is in use.
  void activateClickShield();
  // Called AFTER the panel surface is mapped so the panel wl_surface is
  // available for the whitelist. No-op when focus-grab is unavailable.
  void activateFocusGrab();
  void deactivateOutsideClickHandlers();
  void applyAttachedReveal(float progress);
  void applyDetachedReveal(float progress);
  void publishAttachedPanelGeometry(float revealProgress);
  // Restyle the attached-panel decoration nodes (bg fill, drop shadow, contact shadow)
  // using m_attachedBackgroundOpacity / m_attachedBarPosition. Geometry/positions are not
  // touched. Safe to call any time after buildScene has run.
  void applyAttachedDecorationStyle();
  // Submit a wl_region matching the visible panel body to the compositor for blur.
  // Honors shell.panel.background_blur; clips by m_attachedRevealProgress so the blur
  // grows in lock-step with the open/close animation.
  void applyPanelCompositorBlur();

  WaylandConnection* m_wayland = nullptr;
  ConfigService* m_config = nullptr;
  RenderContext* m_renderContext = nullptr;
  std::function<void()> m_openSettingsWindow;
  std::function<void(wl_output*, std::optional<AttachedPanelGeometry>)> m_attachedPanelGeometryCallback;
  std::function<std::vector<InputRect>(wl_output*)> m_clickShieldExcludeRectsProvider;
  std::function<std::vector<wl_surface*>()> m_focusGrabBarSurfacesProvider;
  PanelClickShield m_clickShield;
  PanelFocusGrab m_focusGrab;

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
  float m_detachedRevealProgress = 1.0f;
  AttachedRevealDirection m_attachedRevealDirection = AttachedRevealDirection::Down;
  std::string m_attachedBarPosition; // "top" / "bottom" / "left" / "right" while attached, empty otherwise
  std::optional<AttachedPanelGeometry> m_attachedPanelGeometry;
  bool m_pointerInside = false;
  bool m_inTransition = false;
  bool m_closing = false;
  bool m_attachedToBar = false;
  std::size_t m_attachedPopupCount = 0;
  ContextMenuPopup* m_activePopup = nullptr;
  std::uint64_t m_destroyGeneration = 0; // invalidates stale deferred destroyPanel calls
};
