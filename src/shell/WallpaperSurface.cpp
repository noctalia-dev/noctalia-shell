#include "shell/WallpaperSurface.h"

#include "render/WallpaperRenderer.h"

std::unique_ptr<Renderer> WallpaperSurface::createRenderer() { return std::make_unique<WallpaperRenderer>(); }
