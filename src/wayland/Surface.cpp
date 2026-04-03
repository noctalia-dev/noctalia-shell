#include "wayland/Surface.hpp"

#include "render/animation/AnimationManager.hpp"
#include "render/GlRenderer.hpp"
#include "render/scene/Node.hpp"
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
                               std::uint32_t callbackData) {
    auto* self = static_cast<Surface*>(data);

    if (callback != nullptr) {
        wl_callback_destroy(callback);
    }

    self->m_frameCallback = nullptr;

    if (self->m_animationManager != nullptr) {
        float deltaMs = 0.0f;
        if (self->m_lastFrameTime != 0 && callbackData > self->m_lastFrameTime) {
            deltaMs = static_cast<float>(callbackData - self->m_lastFrameTime);
        }
        self->m_lastFrameTime = callbackData;
        self->m_animationManager->tick(deltaMs);
    }

    if (self->m_updateCallback) {
        self->m_updateCallback();
    }

    if (self->m_running && self->m_configured) {
        bool dirty = self->m_sceneRoot != nullptr && self->m_sceneRoot->dirty();
        bool animating = self->m_animationManager != nullptr && self->m_animationManager->hasActive();

        if (dirty || animating) {
            self->render();
            self->requestFrame();
        }
        // Frame loop stops here when idle. Restarted by requestRedraw().
    }
}

bool Surface::createWlSurface() {
    m_surface = wl_compositor_create_surface(m_connection.compositor());
    if (m_surface == nullptr) {
        throw std::runtime_error("failed to create wl_surface");
    }

    m_renderer = createRenderer();
    m_renderer->bind(m_connection.display(), m_surface);
    return true;
}

std::unique_ptr<Renderer> Surface::createRenderer() {
    return std::make_unique<GlRenderer>();
}

void Surface::onConfigure(std::uint32_t width, std::uint32_t height) {
    m_width = width;
    m_height = height;
    m_configured = true;

    if (m_renderer == nullptr) {
        m_running = false;
        return;
    }

    if (m_scale > 1) {
        wl_surface_set_buffer_scale(m_surface, m_scale);
    }

    const auto bufferWidth = m_width * static_cast<std::uint32_t>(m_scale);
    const auto bufferHeight = m_height * static_cast<std::uint32_t>(m_scale);
    m_renderer->resize(bufferWidth, bufferHeight, m_width, m_height);
    if (m_configureCallback) {
        m_configureCallback(m_width, m_height);
    }
    render();
}

void Surface::setConfigureCallback(ConfigureCallback callback) {
    m_configureCallback = std::move(callback);
}

void Surface::setUpdateCallback(UpdateCallback callback) {
    m_updateCallback = std::move(callback);
}

void Surface::requestRedraw() {
    if (m_running && m_configured && m_frameCallback == nullptr) {
        // Reset frame time so the first delta after idle is 0,
        // preventing animations from completing instantly due to
        // a stale timestamp from before the surface went idle.
        m_lastFrameTime = 0;
        render();
        requestFrame();
    }
}

void Surface::renderNow() {
    if (m_running && m_configured) {
        render();
    }
}

Renderer* Surface::renderer() const noexcept {
    return m_renderer.get();
}

void Surface::render() {
    if (m_surface == nullptr || m_renderer == nullptr) {
        return;
    }

    requestFrame();
    m_renderer->render();

    if (m_sceneRoot != nullptr) {
        m_sceneRoot->clearDirty();
    }
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
