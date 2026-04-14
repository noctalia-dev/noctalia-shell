#pragma once

#include "render/wallpaper_renderer.h"
#include "wayland/layer_surface.h"

class GlSharedContext;

class WallpaperSurface : public LayerSurface {
public:
  using LayerSurface::LayerSurface;

  [[nodiscard]] WallpaperRenderer* wallpaperRenderer() noexcept { return &m_wallpaperRenderer; }
  void setSharedGl(GlSharedContext* shared) noexcept { m_shared = shared; }

protected:
  bool createWlSurface() override;
  void onConfigure(std::uint32_t width, std::uint32_t height) override;
  void render() override;

private:
  WallpaperRenderer m_wallpaperRenderer;
  GlSharedContext* m_shared = nullptr;
};
