#pragma once

#include "render/animation/animation_manager.h"
#include "render/core/texture_manager.h"
#include "render/programs/wallpaper_program.h"
#include "render/scene/node.h"
#include "render/scene/wallpaper_node.h"
#include "wayland/layer_surface.h"

#include <cstdint>
#include <memory>
#include <string>

class RectNode;

struct WallpaperInstance {
  std::uint32_t outputName = 0;
  struct wl_output* output = nullptr;
  std::int32_t scale = 1;
  std::string connectorName;

  std::unique_ptr<LayerSurface> surface;
  std::unique_ptr<Node> sceneRoot;
  RectNode* fillNode = nullptr;
  WallpaperNode* wallpaperNode = nullptr;
  AnimationManager animations;

  // Wallpaper state
  std::string currentPath;
  std::string pendingPath;
  std::string queuedPath;
  TextureHandle currentTexture;
  TextureHandle nextTexture;

  // Transition state
  float transitionProgress = 0.0f;
  bool transitioning = false;
  AnimationManager::Id transitionAnimId = 0;
  WallpaperTransition activeTransition = WallpaperTransition::Fade;
  TransitionParams transitionParams;
};
