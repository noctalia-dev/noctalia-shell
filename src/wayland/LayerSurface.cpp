#include "wayland/LayerSurface.hpp"

#include "core/Log.hpp"
#include "render/GlRenderer.hpp"
#include "wayland/WaylandConnection.hpp"

#include <stdexcept>
#include <wayland-client.h>

#include "wlr-layer-shell-unstable-v1-client-protocol.h"

namespace {

constexpr std::uint32_t kBarHeight = 36;
constexpr std::uint32_t kAnchorMask =
    ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP |
    ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT |
    ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT;

const zwlr_layer_surface_v1_listener kLayerSurfaceListener = {
    .configure = &LayerSurface::handleConfigure,
    .closed = &LayerSurface::handleClosed,
};

const wl_callback_listener kFrameListener = {
    .done = &LayerSurface::handleFrameDone,
};

} // namespace

LayerSurface::LayerSurface(WaylandConnection& connection)
    : m_connection(connection) {}

LayerSurface::~LayerSurface() {
    cleanup();
}

bool LayerSurface::initialize() {
    if (!m_connection.hasRequiredGlobals()) {
        logWarn("layer surface skipped: missing compositor/shm/layer-shell globals");
        return false;
    }

    if (!createSurface()) {
        return false;
    }

    m_running = true;
    return true;
}

bool LayerSurface::isRunning() const noexcept {
    return m_running;
}

void LayerSurface::dispatch() {
    if (!m_running) {
        return;
    }

    if (wl_display_dispatch(m_connection.display()) < 0) {
        throw std::runtime_error("failed to dispatch Wayland events");
    }
}

void LayerSurface::handleConfigure(void* data,
                                   zwlr_layer_surface_v1* layerSurface,
                                   std::uint32_t serial,
                                   std::uint32_t width,
                                   std::uint32_t height) {
    auto* self = static_cast<LayerSurface*>(data);
    zwlr_layer_surface_v1_ack_configure(layerSurface, serial);

    self->m_width = (width == 0) ? 1920 : width;
    self->m_height = (height == 0) ? kBarHeight : height;
    self->m_configured = true;

    if (self->m_renderer == nullptr) {
        self->m_running = false;
        return;
    }

    self->m_renderer->resize(self->m_width, self->m_height);
    self->render();
}

void LayerSurface::handleClosed(void* data,
                                zwlr_layer_surface_v1* /*layerSurface*/) {
    auto* self = static_cast<LayerSurface*>(data);
    self->m_running = false;
}

void LayerSurface::handleFrameDone(void* data,
                                   wl_callback* callback,
                                   std::uint32_t /*callbackData*/) {
    auto* self = static_cast<LayerSurface*>(data);

    if (callback != nullptr) {
        wl_callback_destroy(callback);
    }

    self->m_frameCallback = nullptr;

    if (self->m_running && self->m_configured) {
        self->requestFrame();
    }
}

bool LayerSurface::createSurface() {
    m_surface = wl_compositor_create_surface(m_connection.compositor());
    if (m_surface == nullptr) {
        throw std::runtime_error("failed to create wl_surface");
    }

    m_renderer = std::make_unique<GlRenderer>();
    m_renderer->bind(m_connection.display(), m_surface);

    wl_output* output = nullptr;
    if (!m_connection.outputs().empty()) {
        output = m_connection.outputs().front().output;
    }

    m_layerSurface = zwlr_layer_shell_v1_get_layer_surface(
        m_connection.layerShell(),
        m_surface,
        output,
        ZWLR_LAYER_SHELL_V1_LAYER_TOP,
        "noctalia-bar");
    if (m_layerSurface == nullptr) {
        throw std::runtime_error("failed to create layer surface");
    }

    if (zwlr_layer_surface_v1_add_listener(m_layerSurface, &kLayerSurfaceListener, this) != 0) {
        throw std::runtime_error("failed to add layer surface listener");
    }

    zwlr_layer_surface_v1_set_anchor(m_layerSurface, kAnchorMask);
    zwlr_layer_surface_v1_set_size(m_layerSurface, 0, kBarHeight);
    zwlr_layer_surface_v1_set_exclusive_zone(m_layerSurface, static_cast<int32_t>(kBarHeight));
    zwlr_layer_surface_v1_set_margin(m_layerSurface, 0, 0, 0, 0);
    zwlr_layer_surface_v1_set_keyboard_interactivity(
        m_layerSurface, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_NONE);

    wl_surface_commit(m_surface);
    if (wl_display_roundtrip(m_connection.display()) < 0) {
        throw std::runtime_error("failed during layer surface initial roundtrip");
    }

    return true;
}

void LayerSurface::render() {
    if (m_surface == nullptr || m_renderer == nullptr) {
        return;
    }

    requestFrame();
    m_renderer->render(m_width, m_height);
}

void LayerSurface::requestFrame() {
    if (m_frameCallback != nullptr) {
        return;
    }

    m_frameCallback = wl_surface_frame(m_surface);
    if (m_frameCallback != nullptr) {
        wl_callback_add_listener(m_frameCallback, &kFrameListener, this);
    }
}

void LayerSurface::cleanup() {
    if (m_frameCallback != nullptr) {
        wl_callback_destroy(m_frameCallback);
        m_frameCallback = nullptr;
    }

    m_renderer.reset();

    if (m_layerSurface != nullptr) {
        zwlr_layer_surface_v1_destroy(m_layerSurface);
        m_layerSurface = nullptr;
    }

    if (m_surface != nullptr) {
        wl_surface_destroy(m_surface);
        m_surface = nullptr;
    }

    m_running = false;
    m_configured = false;
}
