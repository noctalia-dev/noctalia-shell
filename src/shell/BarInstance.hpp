#pragma once

#include "render/AnimationManager.hpp"
#include "render/scene/Node.hpp"
#include "wayland/LayerSurface.hpp"

#include <cstdint>
#include <memory>

class TextNode;

struct BarInstance {
    std::uint32_t outputName = 0;
    wl_output* output = nullptr;
    std::int32_t scale = 1;
    std::unique_ptr<LayerSurface> surface;
    std::unique_ptr<Node> sceneRoot;
    AnimationManager animations;
    TextNode* labelNode = nullptr;
};
