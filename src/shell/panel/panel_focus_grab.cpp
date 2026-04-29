#include "shell/panel/panel_focus_grab.h"

#include "core/log.h"
#include "hyprland-focus-grab-v1-client-protocol.h"
#include "wayland/wayland_connection.h"

namespace {

  constexpr Logger kLog("panel-focus-grab");

  const hyprland_focus_grab_v1_listener kFocusGrabListener = {
      .cleared = &PanelFocusGrab::handleCleared,
  };

} // namespace

PanelFocusGrab::~PanelFocusGrab() { deactivate(); }

void PanelFocusGrab::initialize(WaylandConnection& wayland) { m_wayland = &wayland; }

void PanelFocusGrab::setOnCleared(ClearedCallback callback) { m_onCleared = std::move(callback); }

bool PanelFocusGrab::available() const noexcept {
  return m_wayland != nullptr && m_wayland->hyprlandFocusGrabManager() != nullptr;
}

void PanelFocusGrab::activate(const std::vector<wl_surface*>& surfaces) {
  if (!available()) {
    return;
  }

  // Replace any existing grab. We don't try to diff: panels open infrequently
  // enough that recreating the grab keeps the lifecycle obvious.
  deactivate();

  auto* manager = m_wayland->hyprlandFocusGrabManager();
  m_grab = hyprland_focus_grab_manager_v1_create_grab(manager);
  if (m_grab == nullptr) {
    kLog.warn("create_grab returned null");
    return;
  }

  hyprland_focus_grab_v1_add_listener(m_grab, &kFocusGrabListener, this);

  std::size_t added = 0;
  for (wl_surface* surface : surfaces) {
    if (surface == nullptr) {
      continue;
    }
    hyprland_focus_grab_v1_add_surface(m_grab, surface);
    ++added;
  }

  if (added == 0) {
    // Per protocol, committing an empty whitelist is inert. Tear down so we
    // don't leak the proxy, and so available()/isActive() stay consistent.
    hyprland_focus_grab_v1_destroy(m_grab);
    m_grab = nullptr;
    return;
  }

  hyprland_focus_grab_v1_commit(m_grab);
}

void PanelFocusGrab::deactivate() {
  if (m_grab == nullptr) {
    return;
  }
  hyprland_focus_grab_v1_destroy(m_grab);
  m_grab = nullptr;
}

void PanelFocusGrab::handleCleared(void* data, hyprland_focus_grab_v1* /*grab*/) {
  auto* self = static_cast<PanelFocusGrab*>(data);
  if (self == nullptr) {
    return;
  }
  if (self->m_onCleared) {
    self->m_onCleared();
  }
}
