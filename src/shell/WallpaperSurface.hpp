#pragma once

#include "wayland/LayerSurface.hpp"

#include <memory>

class Renderer;

class WallpaperSurface : public LayerSurface {
public:
    using LayerSurface::LayerSurface;

protected:
    std::unique_ptr<Renderer> createRenderer() override;
};
