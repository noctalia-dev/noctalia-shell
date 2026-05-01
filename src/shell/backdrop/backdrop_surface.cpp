#include "shell/backdrop/backdrop_surface.h"

#include "render/backend/render_backend.h"
#include "render/gl_shared_context.h"
#include "wayland/wayland_connection.h"

#include <stdexcept>
#include <utility>
#include <wayland-client.h>

BackdropSurface::~BackdropSurface() {
  m_wallpaperRenderer.makeCurrent();
  destroyFbos();
}

bool BackdropSurface::createWlSurface() {
  m_surface = wl_compositor_create_surface(m_connection.compositor());
  if (m_surface == nullptr) {
    return false;
  }

  initializeSurfaceScaleProtocol();

  if (m_shared == nullptr) {
    throw std::runtime_error("BackdropSurface requires a GlSharedContext");
  }
  m_wallpaperRenderer.bind(*m_shared, m_surface);
  return true;
}

void BackdropSurface::onConfigure(std::uint32_t width, std::uint32_t height) {
  const auto bw = bufferWidthFor(width);
  const auto bh = bufferHeightFor(height);

  m_bufW = bw;
  m_bufH = bh;

  m_wallpaperRenderer.resize(bw, bh, width, height);

  // Recreate FBOs when buffer size changes (if blur is active)
  if (m_fbo1 != nullptr && m_fbo1->valid()) {
    m_wallpaperRenderer.makeCurrent();
    destroyFbos();
    ensureFbos();
  }

  Surface::onConfigure(width, height);
}

void BackdropSurface::onScaleChanged() {
  if (width() == 0 || height() == 0) {
    return;
  }
  onConfigure(width(), height());
}

void BackdropSurface::render() {
  if (m_surface == nullptr) {
    return;
  }
  if (!m_active) {
    return;
  }

  requestFrame();

  // 3 rounds of H+V blur gives effective sigma ≈ radius * sqrt(3), much stronger result.
  static constexpr int kBlurRounds = 3;
  const float blurRadius = m_blurIntensity * 40.0f;

  ensureFbos();
  if (m_fbo1 == nullptr || !m_fbo1->valid()) {
    return;
  }

  m_wallpaperRenderer.renderToFbo(*m_fbo1);

  if (blurRadius >= 0.5f) {
    if (m_fbo2 == nullptr || !m_fbo2->valid()) {
      return;
    }
    m_wallpaperRenderer.blur(*m_fbo1, *m_fbo2, blurRadius, kBlurRounds);
  }

  if (m_tintIntensity > 0.001f) {
    m_wallpaperRenderer.tint(*m_fbo1, m_tintR, m_tintG, m_tintB, m_tintIntensity);
  }

  m_wallpaperRenderer.blitToSurface(m_fbo1->colorTexture());
  m_wallpaperRenderer.swapBuffers();
}

void BackdropSurface::setActive(bool active) {
  if (m_active == active) {
    return;
  }
  m_active = active;
  if (!m_active && m_unloadWhenInactive) {
    // Free blur render targets while backdrop is inactive to drop VRAM usage.
    m_wallpaperRenderer.makeCurrent();
    destroyFbos();
  }
}

void BackdropSurface::setWallpaperState(TextureId tex, float imgW, float imgH, WallpaperFillMode fillMode) {
  m_wallpaperRenderer.setTransitionState(tex, {}, imgW, imgH, 0.0f, 0.0f, 0.0f, WallpaperTransition::Fade, fillMode,
                                         TransitionParams{});
}

void BackdropSurface::ensureFbos() {
  if ((m_fbo1 != nullptr && m_fbo1->valid()) || m_bufW == 0 || m_bufH == 0) {
    return;
  }

  auto fbo1 = m_wallpaperRenderer.createFramebuffer(m_bufW, m_bufH);
  if (fbo1 == nullptr || !fbo1->valid()) {
    return;
  }

  auto fbo2 = m_wallpaperRenderer.createFramebuffer(m_bufW, m_bufH);
  if (fbo2 == nullptr || !fbo2->valid()) {
    return;
  }

  m_fbo1 = std::move(fbo1);
  m_fbo2 = std::move(fbo2);
}

void BackdropSurface::destroyFbos() {
  m_fbo1.reset();
  m_fbo2.reset();
}
