#include "wayland/popup_surface.h"

#include "core/log.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <stdexcept>
#include <utility>

#include <wayland-client.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#include "xdg-shell-client-protocol.h"

namespace {

  constexpr Logger kLog("wayland");

  const xdg_surface_listener kXdgSurfaceListener = {
      .configure = &PopupSurface::handleXdgSurfaceConfigure,
  };

  const xdg_popup_listener kPopupListener = {
      .configure = &PopupSurface::handlePopupConfigure,
      .popup_done = &PopupSurface::handlePopupDone,
      .repositioned = &PopupSurface::handlePopupRepositioned,
  };

} // namespace

PopupSurface::PopupSurface(WaylandConnection& connection) : Surface(connection) {}

PopupSurface::~PopupSurface() {
  m_connection.unregisterSurface(m_surface);
  destroyRoleObjects();
}

bool PopupSurface::initialize(zwlr_layer_surface_v1* parentLayerSurface, wl_output* output, PopupSurfaceConfig config) {
  if (parentLayerSurface == nullptr || !m_connection.hasXdgShell()) {
    kLog.warn("context menu skipped: missing layer parent or xdg-shell");
    return false;
  }

  if (!createWlSurface()) {
    return false;
  }

  std::int32_t bufferScale = 1;
  if (const auto* wlOutput = m_connection.findOutputByWl(output); wlOutput != nullptr) {
    bufferScale = wlOutput->scale;
  }
  m_connection.registerSurfaceOutput(m_surface, output);
  setBufferScale(bufferScale);

  m_config = config;
  m_config.anchorWidth = std::max(m_config.anchorWidth, 1);
  m_config.anchorHeight = std::max(m_config.anchorHeight, 1);
  m_config.width = std::max(m_config.width, 1u);
  m_config.height = std::max(m_config.height, 1u);

  m_pendingWidth = m_config.width;
  m_pendingHeight = m_config.height;

  m_xdgSurface = xdg_wm_base_get_xdg_surface(m_connection.xdgWmBase(), m_surface);
  if (m_xdgSurface == nullptr) {
    destroySurface();
    return false;
  }
  xdg_surface_add_listener(m_xdgSurface, &kXdgSurfaceListener, this);

  xdg_positioner* positioner = xdg_wm_base_create_positioner(m_connection.xdgWmBase());
  if (positioner == nullptr) {
    destroyRoleObjects();
    destroySurface();
    return false;
  }

  xdg_positioner_set_size(positioner, static_cast<std::int32_t>(m_config.width),
                          static_cast<std::int32_t>(m_config.height));
  xdg_positioner_set_anchor_rect(positioner, m_config.anchorX, m_config.anchorY, m_config.anchorWidth,
                                 m_config.anchorHeight);
  xdg_positioner_set_anchor(positioner, m_config.anchor);
  xdg_positioner_set_gravity(positioner, m_config.gravity);
  xdg_positioner_set_constraint_adjustment(positioner, m_config.constraintAdjustment);
  xdg_positioner_set_offset(positioner, m_config.offsetX, m_config.offsetY);

  m_popup = xdg_surface_get_popup(m_xdgSurface, nullptr, positioner);
  xdg_positioner_destroy(positioner);
  if (m_popup == nullptr) {
    destroyRoleObjects();
    destroySurface();
    return false;
  }

  xdg_popup_add_listener(m_popup, &kPopupListener, this);
  zwlr_layer_surface_v1_get_popup(parentLayerSurface, m_popup);

  if (m_config.grab && m_config.serial != 0 && m_connection.seat() != nullptr) {
    xdg_popup_grab(m_popup, m_connection.seat(), m_config.serial);
  }

  wl_surface_commit(m_surface);
  // Flush before the roundtrip to ensure any pending destroy messages from a previous
  // popup are delivered to the compositor before we ask it to configure the new one.
  wl_display_flush(m_connection.display());
  if (wl_display_roundtrip(m_connection.display()) < 0) {
    kLog.warn("popup: initial roundtrip failed (compositor protocol error)");
    destroyRoleObjects();
    destroySurface();
    return false;
  }

  setRunning(true);
  return true;
}

void PopupSurface::setDismissedCallback(std::function<void()> callback) { m_dismissedCallback = std::move(callback); }

void PopupSurface::handleXdgSurfaceConfigure(void* data, xdg_surface* surface, std::uint32_t serial) {
  auto* self = static_cast<PopupSurface*>(data);
  xdg_surface_ack_configure(surface, serial);

  const std::uint32_t width = self->m_pendingWidth == 0 ? self->m_config.width : self->m_pendingWidth;
  const std::uint32_t height = self->m_pendingHeight == 0 ? self->m_config.height : self->m_pendingHeight;
  self->Surface::onConfigure(std::max(1u, width), std::max(1u, height));
}

void PopupSurface::handlePopupConfigure(void* data, xdg_popup* /*popup*/, std::int32_t x, std::int32_t y,
                                        std::int32_t width, std::int32_t height) {
  auto* self = static_cast<PopupSurface*>(data);
  self->m_configuredX = x;
  self->m_configuredY = y;
  if (width > 0) {
    self->m_pendingWidth = static_cast<std::uint32_t>(width);
  }
  if (height > 0) {
    self->m_pendingHeight = static_cast<std::uint32_t>(height);
  }
}

void PopupSurface::handlePopupDone(void* data, xdg_popup* /*popup*/) {
  auto* self = static_cast<PopupSurface*>(data);
  self->setRunning(false);
  if (self->m_dismissedCallback) {
    self->m_dismissedCallback();
  }
}

void PopupSurface::handlePopupRepositioned(void* /*data*/, xdg_popup* /*popup*/, std::uint32_t /*token*/) {}

bool PopupSurface::initializeAsChild(xdg_surface* parentXdgSurface, wl_output* output, PopupSurfaceConfig config) {
  if (parentXdgSurface == nullptr || !m_connection.hasXdgShell()) {
    kLog.warn("submenu popup skipped: missing parent xdg_surface or xdg-shell");
    return false;
  }

  if (!createWlSurface()) {
    return false;
  }

  std::int32_t bufferScale = 1;
  if (const auto* wlOutput = m_connection.findOutputByWl(output); wlOutput != nullptr) {
    bufferScale = wlOutput->scale;
  }
  m_connection.registerSurfaceOutput(m_surface, output);
  setBufferScale(bufferScale);

  m_config = config;
  m_config.anchorWidth = std::max(m_config.anchorWidth, 1);
  m_config.anchorHeight = std::max(m_config.anchorHeight, 1);
  m_config.width = std::max(m_config.width, 1u);
  m_config.height = std::max(m_config.height, 1u);

  m_pendingWidth = m_config.width;
  m_pendingHeight = m_config.height;

  m_xdgSurface = xdg_wm_base_get_xdg_surface(m_connection.xdgWmBase(), m_surface);
  if (m_xdgSurface == nullptr) {
    destroySurface();
    return false;
  }
  xdg_surface_add_listener(m_xdgSurface, &kXdgSurfaceListener, this);

  xdg_positioner* positioner = xdg_wm_base_create_positioner(m_connection.xdgWmBase());
  if (positioner == nullptr) {
    destroyRoleObjects();
    destroySurface();
    return false;
  }

  xdg_positioner_set_size(positioner, static_cast<std::int32_t>(m_config.width),
                          static_cast<std::int32_t>(m_config.height));
  xdg_positioner_set_anchor_rect(positioner, m_config.anchorX, m_config.anchorY, m_config.anchorWidth,
                                 m_config.anchorHeight);
  xdg_positioner_set_anchor(positioner, m_config.anchor);
  xdg_positioner_set_gravity(positioner, m_config.gravity);
  xdg_positioner_set_constraint_adjustment(positioner, m_config.constraintAdjustment);
  xdg_positioner_set_offset(positioner, m_config.offsetX, m_config.offsetY);

  // popup-of-popup: pass the parent xdg_surface directly
  m_popup = xdg_surface_get_popup(m_xdgSurface, parentXdgSurface, positioner);
  xdg_positioner_destroy(positioner);
  if (m_popup == nullptr) {
    destroyRoleObjects();
    destroySurface();
    return false;
  }

  xdg_popup_add_listener(m_popup, &kPopupListener, this);

  if (m_config.grab && m_config.serial != 0 && m_connection.seat() != nullptr) {
    xdg_popup_grab(m_popup, m_connection.seat(), m_config.serial);
  }

  wl_surface_commit(m_surface);
  wl_display_flush(m_connection.display());
  if (wl_display_roundtrip(m_connection.display()) < 0) {
    kLog.warn("submenu popup: initial roundtrip failed (compositor protocol error)");
    destroyRoleObjects();
    destroySurface();
    return false;
  }

  setRunning(true);
  return true;
}

void PopupSurface::destroyRoleObjects() {
  if (m_popup != nullptr) {
    xdg_popup_destroy(m_popup);
    m_popup = nullptr;
  }
  if (m_xdgSurface != nullptr) {
    xdg_surface_destroy(m_xdgSurface);
    m_xdgSurface = nullptr;
  }
}
