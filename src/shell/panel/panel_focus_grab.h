#pragma once

#include <functional>
#include <vector>

class WaylandConnection;
struct hyprland_focus_grab_v1;
struct wl_surface;

// Thin wrapper around hyprland_focus_grab_v1. While active, the compositor
// dispatches pointer/touch events landing inside any whitelisted surface to
// that surface as usual; a click that lands outside the whitelist clears the
// grab and fires `cleared`. We use this on Hyprland in lieu of the click
// shield: same outcome (panel dismisses on outside click) without fighting
// Hyprland's layer-shell input quirks.
//
// Lifecycle:
//   - activate(...) creates a fresh grab, adds the given surfaces, commits.
//   - deactivate() destroys the grab.
//   - On `cleared` the wrapper invokes onCleared (if set). The wrapper does
//     NOT auto-deactivate; the owner (PanelManager) decides what to do.
//
// `available()` is true only when the compositor advertises the protocol —
// i.e. on Hyprland builds that support it. Callers should check this and
// fall back to PanelClickShield otherwise.
class PanelFocusGrab {
public:
  using ClearedCallback = std::function<void()>;

  PanelFocusGrab() = default;
  ~PanelFocusGrab();

  PanelFocusGrab(const PanelFocusGrab&) = delete;
  PanelFocusGrab& operator=(const PanelFocusGrab&) = delete;

  void initialize(WaylandConnection& wayland);
  void setOnCleared(ClearedCallback callback);

  [[nodiscard]] bool available() const noexcept;
  [[nodiscard]] bool isActive() const noexcept { return m_grab != nullptr; }

  // Create a grab and seed its whitelist with `surfaces`. Any surface that
  // is null is skipped. Replaces a previous grab if one is already active.
  void activate(const std::vector<wl_surface*>& surfaces);

  // Destroy the grab if active. Idempotent.
  void deactivate();

  // Public so the C-callback bridge in panel_focus_grab.cpp can dispatch.
  static void handleCleared(void* data, hyprland_focus_grab_v1* grab);

private:
  WaylandConnection* m_wayland = nullptr;
  hyprland_focus_grab_v1* m_grab = nullptr;
  ClearedCallback m_onCleared;
};
