#pragma once

#include "config/config_service.h"
#include "render/animation/animation_manager.h"
#include "render/scene/input_dispatcher.h"
#include "render/scene/node.h"
#include "shell/widget/widget.h"
#include "wayland/layer_surface.h"

#include <cstdint>
#include <memory>
#include <vector>

class Box;

struct BarInstance {
  std::uint32_t outputName = 0;
  wl_output* output = nullptr;
  std::int32_t scale = 1;
  std::size_t barIndex = 0;
  BarConfig barConfig;
  std::unique_ptr<LayerSurface> surface;
  std::unique_ptr<Node> sceneRoot;
  AnimationManager animations;
  InputDispatcher inputDispatcher;

  // Bar layout sections (start/center/end along main axis)
  Box* startSection = nullptr;
  Box* centerSection = nullptr;
  Box* endSection = nullptr;

  std::vector<std::unique_ptr<Widget>> startWidgets;
  std::vector<std::unique_ptr<Widget>> centerWidgets;
  std::vector<std::unique_ptr<Widget>> endWidgets;
};
