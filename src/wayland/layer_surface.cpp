#include "wayland/layer_surface.h"

#include "core/log.h"
#include "wayland/wayland_connection.h"

#include <stdexcept>
#include <wayland-client.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"

namespace {

const zwlr_layer_surface_v1_listener kLayerSurfaceListener = {
    .configure = &LayerSurface::handleConfigure,
    .closed = &LayerSurface::handleClosed,
};

} // namespace

LayerSurface::LayerSurface(WaylandConnection& connection, LayerSurfaceConfig config)
    : Surface(connection), m_config(std::move(config)) {}

LayerSurface::~LayerSurface() {
  if (m_layerSurface != nullptr) {
    zwlr_layer_surface_v1_destroy(m_layerSurface);
    m_layerSurface = nullptr;
  }
}

bool LayerSurface::initialize() {
  wl_output* output = nullptr;
  std::int32_t scale = 1;
  if (!m_connection.outputs().empty()) {
    output = m_connection.outputs().front().output;
    scale = m_connection.outputs().front().scale;
  }
  return initialize(output, scale);
}

bool LayerSurface::initialize(wl_output* output, std::int32_t scale) {
  if (!m_connection.hasRequiredGlobals()) {
    logWarn("layer surface skipped: missing compositor/shm/layer-shell globals");
    return false;
  }

  if (!createWlSurface()) {
    return false;
  }

  setScale(scale);

  m_layerSurface =
      zwlr_layer_shell_v1_get_layer_surface(m_connection.layerShell(), m_surface, output,
                                            static_cast<std::uint32_t>(m_config.layer), m_config.nameSpace.c_str());
  if (m_layerSurface == nullptr) {
    throw std::runtime_error("failed to create layer surface");
  }

  if (zwlr_layer_surface_v1_add_listener(m_layerSurface, &kLayerSurfaceListener, this) != 0) {
    throw std::runtime_error("failed to add layer surface listener");
  }

  zwlr_layer_surface_v1_set_anchor(m_layerSurface, m_config.anchor);
  zwlr_layer_surface_v1_set_size(m_layerSurface, m_config.width, m_config.height);
  zwlr_layer_surface_v1_set_exclusive_zone(m_layerSurface, m_config.exclusiveZone);
  zwlr_layer_surface_v1_set_margin(m_layerSurface, m_config.marginTop, m_config.marginRight, m_config.marginBottom,
                                   m_config.marginLeft);
  zwlr_layer_surface_v1_set_keyboard_interactivity(m_layerSurface, static_cast<std::uint32_t>(m_config.keyboard));

  wl_surface_commit(m_surface);
  if (wl_display_roundtrip(m_connection.display()) < 0) {
    throw std::runtime_error("failed during layer surface initial roundtrip");
  }

  setRunning(true);
  return true;
}

void LayerSurface::handleConfigure(void* data, zwlr_layer_surface_v1* layerSurface, std::uint32_t serial,
                                   std::uint32_t width, std::uint32_t height) {
  auto* self = static_cast<LayerSurface*>(data);
  zwlr_layer_surface_v1_ack_configure(layerSurface, serial);

  self->onConfigure((width == 0) ? self->m_config.defaultWidth : width,
                    (height == 0) ? self->m_config.defaultHeight : height);
}

void LayerSurface::handleClosed(void* data, zwlr_layer_surface_v1* /*layerSurface*/) {
  auto* self = static_cast<LayerSurface*>(data);
  self->setRunning(false);
}
