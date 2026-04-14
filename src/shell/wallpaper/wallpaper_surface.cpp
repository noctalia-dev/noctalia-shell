#include "shell/wallpaper/wallpaper_surface.h"

#include "render/gl_shared_context.h"
#include "wayland/wayland_connection.h"

#include <stdexcept>
#include <wayland-client.h>

bool WallpaperSurface::createWlSurface() {
  m_surface = wl_compositor_create_surface(m_connection.compositor());
  if (m_surface == nullptr) {
    return false;
  }

  if (m_shared == nullptr) {
    throw std::runtime_error("WallpaperSurface requires a GlSharedContext");
  }
  m_wallpaperRenderer.bind(*m_shared, m_surface);
  return true;
}

void WallpaperSurface::onConfigure(std::uint32_t width, std::uint32_t height) {
  const auto bufferWidth = width * static_cast<std::uint32_t>(bufferScale());
  const auto bufferHeight = height * static_cast<std::uint32_t>(bufferScale());
  m_wallpaperRenderer.resize(bufferWidth, bufferHeight, width, height);

  // Call base for bookkeeping (sets width/height/configured, calls configureCallback, calls render)
  Surface::onConfigure(width, height);
}

void WallpaperSurface::render() {
  if (m_surface == nullptr) {
    return;
  }

  requestFrame();
  m_wallpaperRenderer.render();
}
