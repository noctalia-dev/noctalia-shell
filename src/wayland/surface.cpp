#include "wayland/surface.h"

#include "core/ui_phase.h"
#include "ext-background-effect-v1-client-protocol.h"
#include "render/animation/animation_manager.h"
#include "render/render_context.h"
#include "render/scene/node.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cmath>
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
  self->m_inFrameHandler = true;

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

  self->m_inFrameHandler = false;

  self->preparePendingFrame();

  if (self->m_running && self->m_configured) {
    const bool invalidated =
        self->m_sceneRoot != nullptr && (self->m_sceneRoot->paintDirty() || self->m_sceneRoot->layoutDirty());
    const bool animating = self->m_animationManager != nullptr && self->m_animationManager->hasActive();
    const bool redrawRequested = self->m_redrawRequested;

    if (invalidated || animating || redrawRequested) {
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

void Surface::setBlurRegion(const std::vector<InputRect>& rects) {
  if (m_surface == nullptr || !m_connection.hasBackgroundEffectBlur()) {
    return;
  }

  if (m_backgroundEffect == nullptr) {
    auto* manager = m_connection.backgroundEffectManager();
    if (manager == nullptr) {
      return;
    }
    m_backgroundEffect = ext_background_effect_manager_v1_get_background_effect(manager, m_surface);
    if (m_backgroundEffect == nullptr) {
      return;
    }
  }

  wl_region* region = nullptr;
  if (!rects.empty()) {
    region = wl_compositor_create_region(m_connection.compositor());
    if (region == nullptr) {
      return;
    }
    for (const auto& r : rects) {
      wl_region_add(region, r.x, r.y, r.width, r.height);
    }
  }
  ext_background_effect_surface_v1_set_blur_region(m_backgroundEffect, region);
  if (region != nullptr) {
    wl_region_destroy(region);
  }
}

std::vector<InputRect> Surface::tessellateRoundedRect(int x, int y, int w, int h, float tlRadius, float trRadius,
                                                      float brRadius, float blRadius, int stripPx) {
  std::vector<InputRect> out;
  if (w <= 0 || h <= 0) {
    return out;
  }

  if (stripPx < 1) {
    stripPx = 1;
  }

  const float halfW = static_cast<float>(w) * 0.5f;
  const float halfH = static_cast<float>(h) * 0.5f;
  const float maxRadius = std::min(halfW, halfH);
  const auto clampR = [maxRadius](float r) {
    if (r < 0.0f)
      return 0.0f;
    return std::min(r, maxRadius);
  };
  const float tl = clampR(tlRadius);
  const float tr = clampR(trRadius);
  const float br = clampR(brRadius);
  const float bl = clampR(blRadius);

  const int topBand = static_cast<int>(std::ceil(std::max(tl, tr)));
  const int bottomBand = static_cast<int>(std::ceil(std::max(bl, br)));
  const int middleY = y + topBand;
  const int middleH = h - topBand - bottomBand;

  const auto inset = [](float r, float distFromCornerEdge) -> float {
    if (r <= 0.0f)
      return 0.0f;
    const float dy = r - distFromCornerEdge;
    if (dy <= 0.0f)
      return 0.0f;
    const float ry = std::sqrt(std::max(0.0f, r * r - dy * dy));
    return r - ry;
  };

  out.reserve(static_cast<std::size_t>((topBand + bottomBand) / stripPx + 2));

  // Top corner band: strips run from y..y+topBand, distFromTop grows downward.
  for (int row = 0; row < topBand; row += stripPx) {
    const int rowH = std::min(stripPx, topBand - row);
    // Use the strip's bottom edge for the inset sample so the polygon stays inside the curve.
    const float sample = static_cast<float>(row + rowH);
    const float leftInset = inset(tl, sample);
    const float rightInset = inset(tr, sample);
    const int rx = x + static_cast<int>(std::ceil(leftInset));
    const int rw = w - static_cast<int>(std::ceil(leftInset)) - static_cast<int>(std::ceil(rightInset));
    if (rw > 0) {
      out.push_back({rx, y + row, rw, rowH});
    }
  }

  // Middle full-width band.
  if (middleH > 0) {
    out.push_back({x, middleY, w, middleH});
  }

  // Bottom corner band: distFromBottom shrinks as we move down.
  for (int row = 0; row < bottomBand; row += stripPx) {
    const int rowFromTop = row;
    const int rowH = std::min(stripPx, bottomBand - rowFromTop);
    // Sample at the strip's top edge (distance from bottom edge of the rect).
    const float sample = static_cast<float>(bottomBand - rowFromTop);
    const float leftInset = inset(bl, sample);
    const float rightInset = inset(br, sample);
    const int rx = x + static_cast<int>(std::ceil(leftInset));
    const int rw = w - static_cast<int>(std::ceil(leftInset)) - static_cast<int>(std::ceil(rightInset));
    if (rw > 0) {
      out.push_back({rx, middleY + middleH + rowFromTop, rw, rowH});
    }
  }

  return out;
}

void Surface::clearBlurRegion() {
  if (m_backgroundEffect == nullptr) {
    return;
  }
  ext_background_effect_surface_v1_destroy(m_backgroundEffect);
  m_backgroundEffect = nullptr;
}

void Surface::requestUpdate() {
  m_updateRequested = true;
  m_layoutRequested = true;
  kickFrameLoop();
}

void Surface::requestUpdateOnly() {
  m_updateRequested = true;
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

  if (m_backgroundEffect != nullptr) {
    ext_background_effect_surface_v1_destroy(m_backgroundEffect);
    m_backgroundEffect = nullptr;
  }

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

  UiPhaseScope preparePhase(UiPhase::PrepareFrame);
  const bool needsUpdate = m_updateRequested;
  const bool needsLayout = m_layoutRequested;
  m_updateRequested = false;
  m_layoutRequested = false;
  m_prepareFrameCallback(needsUpdate, needsLayout);
}

void Surface::kickFrameLoop() {
  if (!m_running || !m_configured || m_frameCallback != nullptr || m_inFrameHandler) {
    return;
  }

  // Anchor the animation clock at "now" instead of clearing it. On the next
  // handleFrameDone, deltaMs is computed against this anchor, so animations
  // that start while the surface was idle get a real first-tick deltaMs
  // instead of zero (which would waste the first tick at t=0).
  m_lastFrameAt = std::chrono::steady_clock::now();
  preparePendingFrame();

  const bool invalidated = m_sceneRoot != nullptr && (m_sceneRoot->paintDirty() || m_sceneRoot->layoutDirty());
  const bool animating = m_animationManager != nullptr && m_animationManager->hasActive();
  if (m_redrawRequested || invalidated || animating) {
    m_redrawRequested = false;
    render();
  }
}
