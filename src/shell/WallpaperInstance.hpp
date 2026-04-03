#pragma once

#include "render/animation/AnimationManager.hpp"
#include "render/core/TextureManager.hpp"
#include "render/programs/WallpaperProgram.hpp"
#include "shell/WallpaperSurface.hpp"

#include <cstdint>
#include <memory>
#include <string>

struct WallpaperInstance {
    std::uint32_t outputName = 0;
    struct wl_output* output = nullptr;
    std::int32_t scale = 1;
    std::string connectorName;

    std::unique_ptr<WallpaperSurface> surface;
    AnimationManager animations;

    // Wallpaper state
    std::string currentPath;
    std::string pendingPath;
    TextureHandle currentTexture;
    TextureHandle nextTexture;

    // Transition state
    float transitionProgress = 0.0f;
    bool transitioning = false;
    TransitionParams transitionParams;
};
