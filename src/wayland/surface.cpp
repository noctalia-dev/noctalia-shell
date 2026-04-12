#include "wayland/surface.h"

#include "render/animation/animation_manager.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "wayland/wayland_connection.h"

#include <wayland-client.h>

namespace {

  const wl_callback_listener kFrameListener = {
      .done = &Surface::handleFrameDone,
  };

} // namespace

Surface::Surface(WaylandConnection& connection) : m_connection(connection) {}

Surface::~Surface() { destroySurface(); }

bool Surface::isRunning() const noexcept { return m_running; }

void Surface::handleFrameDone(void* data, wl_callback* callback, std::uint32_t callbackData) {
  auto* self = static_cast<Surface*>(data);
  (void)callbackData;

  if (callback != nullptr) {
    wl_callback_destroy(callback);
  }

  self->m_frameCallback = nullptr;

  float deltaMs = 0.0f;
  const auto now = std::chrono::steady_clock::now();
  if (self->m_lastFrameAt.has_value()) {
    deltaMs = std::chrono::duration<float, std::milli>(now - *self->m_lastFrameAt).count();
  }
  self->m_lastFrameAt = now;

  if (self->m_animationManager != nullptr) {
    self->m_animationManager->tick(deltaMs);
  }

  if (self->m_frameTickCallback) {
    self->m_frameTickCallback(deltaMs);
  }

  if (self->m_updateCallback) {
    self->m_updateCallback();
  }

  self->preparePendingFrame();

  if (self->m_running && self->m_configured) {
    bool dirty = self->m_sceneRoot != nullptr && self->m_sceneRoot->dirty();
    bool animating = self->m_animationManager != nullptr && self->m_animationManager->hasActive();
    bool redrawRequested = self->m_redrawRequested;

    if (dirty || animating || redrawRequested) {
      self->m_redrawRequested = false;
      self->render();
    }
    // Frame loop stops here when idle. Restarted by requestRedraw().
  }
}

bool Surface::createWlSurface() {
  m_surface = wl_compositor_create_surface(m_connection.compositor());
  if (m_surface == nullptr) {
    return false;
  }

  if (m_renderContext != nullptr) {
    m_renderTarget.create(m_surface, *m_renderContext);
  }
  return true;
}

void Surface::onConfigure(std::uint32_t width, std::uint32_t height) {
  m_width = width;
  m_height = height;
  m_configured = true;

  if (m_bufferScale > 1) {
    wl_surface_set_buffer_scale(m_surface, m_bufferScale);
  }

  if (m_renderContext != nullptr) {
    const auto bufferWidth = m_width * static_cast<std::uint32_t>(m_bufferScale);
    const auto bufferHeight = m_height * static_cast<std::uint32_t>(m_bufferScale);
    m_renderTarget.setLogicalSize(m_width, m_height);
    m_renderTarget.resize(bufferWidth, bufferHeight);
  }

  if (m_configureCallback) {
    m_configureCallback(m_width, m_height);
  }
  preparePendingFrame();
  render();
}

void Surface::setConfigureCallback(ConfigureCallback callback) { m_configureCallback = std::move(callback); }

void Surface::setPrepareFrameCallback(PrepareFrameCallback callback) { m_prepareFrameCallback = std::move(callback); }

void Surface::setUpdateCallback(UpdateCallback callback) { m_updateCallback = std::move(callback); }

void Surface::setFrameTickCallback(FrameTickCallback callback) { m_frameTickCallback = std::move(callback); }

void Surface::setInputRegion(const std::vector<InputRect>& rects) {
  if (m_surface == nullptr) {
    return;
  }

  wl_region* region = wl_compositor_create_region(m_connection.compositor());
  if (region == nullptr) {
    return;
  }

  for (const auto& r : rects) {
    wl_region_add(region, r.x, r.y, r.width, r.height);
  }

  wl_surface_set_input_region(m_surface, region);
  wl_region_destroy(region);
}

void Surface::requestUpdate() {
  m_updateRequested = true;
  m_layoutRequested = true;
  kickFrameLoop();
}

void Surface::requestLayout() {
  m_layoutRequested = true;
  kickFrameLoop();
}

void Surface::requestRedraw() {
  m_redrawRequested = true;
  kickFrameLoop();
}

void Surface::renderNow() {
  if (m_running && m_configured) {
    preparePendingFrame();
    render();
  }
}

void Surface::render() {
  if (m_surface == nullptr || m_renderContext == nullptr || !m_renderTarget.isReady()) {
    return;
  }

  requestFrame();
  m_renderContext->renderScene(m_renderTarget, m_sceneRoot);

  if (m_sceneRoot != nullptr) {
    m_sceneRoot->clearDirty();
  }
  m_redrawRequested = false;
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

  m_renderTarget.destroy();

  if (m_surface != nullptr) {
    wl_surface_destroy(m_surface);
    m_surface = nullptr;
  }

  m_running = false;
  m_configured = false;
}

void Surface::preparePendingFrame() {
  if (m_prepareFrameCallback == nullptr || (!m_updateRequested && !m_layoutRequested)) {
    return;
  }

  const bool needsUpdate = m_updateRequested;
  const bool needsLayout = m_layoutRequested;
  m_updateRequested = false;
  m_layoutRequested = false;
  m_prepareFrameCallback(needsUpdate, needsLayout);
}

void Surface::kickFrameLoop() {
  if (!m_running || !m_configured || m_frameCallback != nullptr) {
    return;
  }

  m_lastFrameAt.reset();
  preparePendingFrame();

  const bool dirty = m_sceneRoot != nullptr && m_sceneRoot->dirty();
  const bool animating = m_animationManager != nullptr && m_animationManager->hasActive();
  if (m_redrawRequested || dirty || animating) {
    m_redrawRequested = false;
    render();
  }
}
