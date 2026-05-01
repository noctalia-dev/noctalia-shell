#include "shell/backdrop/backdrop_surface.h"

#include "render/backend/render_backend.h"
#include "render/gl_shared_context.h"
#include "wayland/wayland_connection.h"

#include <stdexcept>
#include <utility>
#include <wayland-client.h>

BackdropSurface::~BackdropSurface() {
  m_wallpaperRenderer.makeCurrent();
  destroyFramebuffers();
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

  // Recreate offscreen framebuffers when buffer size changes.
  if (m_primaryFramebuffer != nullptr && m_primaryFramebuffer->valid()) {
    m_wallpaperRenderer.makeCurrent();
    destroyFramebuffers();
    ensureFramebuffers();
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
  const auto options = BackdropPostProcessOptions{
      .blurRadius = m_blurIntensity * 40.0f,
      .blurRounds = kBlurRounds,
      .tintColor = rgba(m_tintR, m_tintG, m_tintB, 1.0f),
      .tintIntensity = m_tintIntensity,
  };

  ensureFramebuffers();
  if (m_primaryFramebuffer == nullptr || m_scratchFramebuffer == nullptr || !m_primaryFramebuffer->valid() ||
      !m_scratchFramebuffer->valid()) {
    return;
  }

  m_wallpaperRenderer.renderBackdropFrame(*m_primaryFramebuffer, *m_scratchFramebuffer, options);
}

void BackdropSurface::setActive(bool active) {
  if (m_active == active) {
    return;
  }
  m_active = active;
  if (!m_active && m_unloadWhenInactive) {
    // Free blur render targets while backdrop is inactive to drop VRAM usage.
    m_wallpaperRenderer.makeCurrent();
    destroyFramebuffers();
  }
}

void BackdropSurface::setWallpaperState(TextureId tex, float imgW, float imgH, WallpaperFillMode fillMode) {
  m_wallpaperRenderer.setTransitionState(tex, {}, imgW, imgH, 0.0f, 0.0f, 0.0f, WallpaperTransition::Fade, fillMode,
                                         TransitionParams{});
}

void BackdropSurface::ensureFramebuffers() {
  if ((m_primaryFramebuffer != nullptr && m_primaryFramebuffer->valid()) || m_bufW == 0 || m_bufH == 0) {
    return;
  }

  auto primary = m_wallpaperRenderer.createFramebuffer(m_bufW, m_bufH);
  if (primary == nullptr || !primary->valid()) {
    return;
  }

  auto scratch = m_wallpaperRenderer.createFramebuffer(m_bufW, m_bufH);
  if (scratch == nullptr || !scratch->valid()) {
    return;
  }

  m_primaryFramebuffer = std::move(primary);
  m_scratchFramebuffer = std::move(scratch);
}

void BackdropSurface::destroyFramebuffers() {
  m_primaryFramebuffer.reset();
  m_scratchFramebuffer.reset();
}
