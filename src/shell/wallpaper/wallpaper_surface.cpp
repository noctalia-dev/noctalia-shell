#include "shell/wallpaper/wallpaper_surface.h"

#include "wayland/wayland_connection.h"

#include <wayland-client.h>

bool WallpaperSurface::createWlSurface() {
  m_surface = wl_compositor_create_surface(m_connection.compositor());
  if (m_surface == nullptr) {
    return false;
  }

  m_wallpaperRenderer.bind(m_connection.display(), m_surface, m_shareContext);
  return true;
}

void WallpaperSurface::onConfigure(std::uint32_t width, std::uint32_t height) {
  const auto bufferWidth = width * static_cast<std::uint32_t>(scale());
  const auto bufferHeight = height * static_cast<std::uint32_t>(scale());
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
