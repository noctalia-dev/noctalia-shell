#pragma once

#include "render/wallpaper_renderer.h"
#include "wayland/layer_surface.h"

class WallpaperSurface : public LayerSurface {
public:
  using LayerSurface::LayerSurface;

  [[nodiscard]] WallpaperRenderer* wallpaperRenderer() noexcept { return &m_wallpaperRenderer; }
  void setShareContext(EGLContext ctx) noexcept { m_shareContext = ctx; }

protected:
  bool createWlSurface() override;
  void onConfigure(std::uint32_t width, std::uint32_t height) override;
  void render() override;

private:
  WallpaperRenderer m_wallpaperRenderer;
  EGLContext m_shareContext = EGL_NO_CONTEXT;
};
