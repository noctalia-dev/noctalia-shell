#pragma once

#include "render/scene/Node.hpp"

#include <memory>

class AnimationManager;
class Renderer;

class Widget {
public:
    virtual ~Widget() = default;

    virtual void create(Renderer& renderer) = 0;
    virtual void layout(Renderer& renderer, float barWidth, float barHeight) = 0;
    virtual void update(Renderer& renderer);

    [[nodiscard]] Node* root() const noexcept { return m_root ? m_root.get() : m_rootPtr; }
    [[nodiscard]] float width() const noexcept;
    [[nodiscard]] float height() const noexcept;

    // Transfer ownership of root node to caller (e.g., for adding to a Box).
    // Widget keeps a raw pointer for updates.
    std::unique_ptr<Node> releaseRoot();

    void setAnimationManager(AnimationManager* mgr) noexcept;

protected:
    std::unique_ptr<Node> m_root;
    Node* m_rootPtr = nullptr;
    AnimationManager* m_animations = nullptr;
};
