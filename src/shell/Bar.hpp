#pragma once

#include "render/scene/Node.hpp"
#include "wayland/LayerSurface.hpp"
#include "wayland/WaylandConnection.hpp"

#include <memory>

class TextNode;

class Bar {
public:
    Bar();

    bool initialize();
    [[nodiscard]] bool isRunning() const noexcept;
    [[nodiscard]] int displayFd() const noexcept;
    void dispatchPending();
    void dispatchReadable();
    void flush();
    const WaylandConnection& connection() const noexcept;

private:
    void buildScene(std::uint32_t width, std::uint32_t height);

    WaylandConnection m_connection;
    LayerSurface m_layerSurface;
    std::unique_ptr<Node> m_sceneRoot;
    TextNode* m_labelNode = nullptr;
};
