#pragma once

#include "render/AnimationManager.hpp"
#include "render/scene/Node.hpp"
#include "ui/Widget.hpp"
#include "wayland/LayerSurface.hpp"

#include <cstdint>
#include <memory>
#include <vector>

class Box;

struct BarInstance {
    std::uint32_t outputName = 0;
    wl_output* output = nullptr;
    std::int32_t scale = 1;
    std::unique_ptr<LayerSurface> surface;
    std::unique_ptr<Node> sceneRoot;
    AnimationManager animations;

    // Bar layout sections (start/center/end along main axis)
    Box* startSection = nullptr;
    Box* centerSection = nullptr;
    Box* endSection = nullptr;

    std::vector<std::unique_ptr<Widget>> startWidgets;
    std::vector<std::unique_ptr<Widget>> centerWidgets;
    std::vector<std::unique_ptr<Widget>> endWidgets;
};
