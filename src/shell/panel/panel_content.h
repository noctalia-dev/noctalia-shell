#pragma once

#include "render/scene/node.h"

#include <memory>

class AnimationManager;
class Renderer;

class PanelContent {
public:
  virtual ~PanelContent() = default;

  virtual void create(Renderer& renderer) = 0;
  virtual void layout(Renderer& renderer, float width, float height) = 0;
  virtual void update(Renderer& renderer) = 0;

  [[nodiscard]] virtual float preferredWidth() const = 0;
  [[nodiscard]] virtual float preferredHeight() const = 0;

  [[nodiscard]] Node* root() const noexcept { return m_root ? m_root.get() : m_rootPtr; }

  std::unique_ptr<Node> releaseRoot() {
    m_rootPtr = m_root.get();
    return std::move(m_root);
  }

  void setAnimationManager(AnimationManager* mgr) noexcept { m_animations = mgr; }

protected:
  std::unique_ptr<Node> m_root;
  Node* m_rootPtr = nullptr;
  AnimationManager* m_animations = nullptr;
};
