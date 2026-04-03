#include "wayland/Surface.hpp"

#include "render/GlRenderer.hpp"
#include "wayland/WaylandConnection.hpp"

#include <stdexcept>
#include <wayland-client.h>

namespace {

const wl_callback_listener kFrameListener = {
    .done = &Surface::handleFrameDone,
};

} // namespace

Surface::Surface(WaylandConnection& connection)
    : m_connection(connection) {}

Surface::~Surface() {
    destroySurface();
}

bool Surface::isRunning() const noexcept {
    return m_running;
}

void Surface::handleFrameDone(void* data,
                               wl_callback* callback,
                               std::uint32_t /*callbackData*/) {
    auto* self = static_cast<Surface*>(data);

    if (callback != nullptr) {
        wl_callback_destroy(callback);
    }

    self->m_frameCallback = nullptr;

    if (self->m_running && self->m_configured) {
        self->requestFrame();
    }
}

bool Surface::createWlSurface() {
    m_surface = wl_compositor_create_surface(m_connection.compositor());
    if (m_surface == nullptr) {
        throw std::runtime_error("failed to create wl_surface");
    }

    m_renderer = std::make_unique<GlRenderer>();
    m_renderer->bind(m_connection.display(), m_surface);
    return true;
}

void Surface::onConfigure(std::uint32_t width, std::uint32_t height) {
    m_width = width;
    m_height = height;
    m_configured = true;

    if (m_renderer == nullptr) {
        m_running = false;
        return;
    }

    m_renderer->resize(m_width, m_height);
    if (m_configureCallback) {
        m_configureCallback(m_width, m_height);
    }
    render();
}

void Surface::setConfigureCallback(ConfigureCallback callback) {
    m_configureCallback = std::move(callback);
}

Renderer* Surface::renderer() const noexcept {
    return m_renderer.get();
}

void Surface::render() {
    if (m_surface == nullptr || m_renderer == nullptr) {
        return;
    }

    requestFrame();
    m_renderer->render(m_width, m_height);
}

void Surface::requestFrame() {
    if (m_frameCallback != nullptr) {
        return;
    }

    m_frameCallback = wl_surface_frame(m_surface);
    if (m_frameCallback != nullptr) {
        wl_callback_add_listener(m_frameCallback, &kFrameListener, this);
    }
}

void Surface::destroySurface() {
    if (m_frameCallback != nullptr) {
        wl_callback_destroy(m_frameCallback);
        m_frameCallback = nullptr;
    }

    m_renderer.reset();

    if (m_surface != nullptr) {
        wl_surface_destroy(m_surface);
        m_surface = nullptr;
    }

    m_running = false;
    m_configured = false;
}
