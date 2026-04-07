#pragma once

#include "render/scene/node.h"
#include "wayland/layer_surface.h"

#include <memory>
#include <string_view>

class AnimationManager;
class InputArea;
class Renderer;

class Panel {
public:
  virtual ~Panel() = default;

  virtual void create(Renderer& renderer) = 0;
  virtual void layout(Renderer& renderer, float width, float height) = 0;
  virtual void update(Renderer& renderer) = 0;
  virtual void onOpen(std::string_view context) { (void)context; }
  virtual void onClose() {}

  [[nodiscard]] virtual float preferredWidth() const = 0;
  [[nodiscard]] virtual float preferredHeight() const = 0;
  [[nodiscard]] virtual bool centered() const { return false; }
  [[nodiscard]] virtual bool centeredVertically() const { return false; }
  [[nodiscard]] virtual LayerShellLayer layer() const { return LayerShellLayer::Top; }
  [[nodiscard]] virtual LayerShellKeyboard keyboardMode() const { return LayerShellKeyboard::OnDemand; }
  [[nodiscard]] virtual InputArea* initialFocusArea() const { return nullptr; }

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
