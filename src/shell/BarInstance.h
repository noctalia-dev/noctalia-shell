#pragma once

#include "config/ConfigService.h"
#include "render/animation/AnimationManager.h"
#include "render/scene/Node.h"
#include "shell/Widget.h"
#include "wayland/LayerSurface.h"

#include <cstdint>
#include <memory>
#include <unordered_map>
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

    // Bar layout sections (start/center/end along main axis)
    Box* startSection = nullptr;
    Box* centerSection = nullptr;
    Box* endSection = nullptr;

    std::vector<std::unique_ptr<Widget>> startWidgets;
    std::vector<std::unique_ptr<Widget>> centerWidgets;
    std::vector<std::unique_ptr<Widget>> endWidgets;

    // Maps widget root Node* → Widget* for input dispatch
    std::unordered_map<Node*, Widget*> widgetNodeMap;
};
