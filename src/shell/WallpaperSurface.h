#pragma once

#include "render/WallpaperRenderer.h"
#include "wayland/LayerSurface.h"

class WallpaperSurface : public LayerSurface {
public:
  using LayerSurface::LayerSurface;

  [[nodiscard]] WallpaperRenderer* wallpaperRenderer() noexcept { return &m_wallpaperRenderer; }

protected:
  bool createWlSurface() override;
  void onConfigure(std::uint32_t width, std::uint32_t height) override;
  void render() override;

private:
  WallpaperRenderer m_wallpaperRenderer;
};
