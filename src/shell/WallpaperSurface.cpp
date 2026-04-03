#include "shell/WallpaperSurface.hpp"

#include "render/WallpaperRenderer.hpp"

std::unique_ptr<Renderer> WallpaperSurface::createRenderer() {
    return std::make_unique<WallpaperRenderer>();
}
