#pragma once

#include "render/scene/node.h"

#include <functional>
#include <memory>

class AnimationManager;
class Renderer;

class Widget {
public:
  using RedrawCallback = std::function<void()>;

  virtual ~Widget() = default;

  virtual void create() = 0;
  virtual void layout(Renderer& renderer, float containerWidth, float containerHeight) = 0;
  virtual void update(Renderer& renderer);

  // Input events. Coordinates are widget-local (relative to widget root node).
  virtual void onPointerEnter(float localX, float localY);
  virtual void onPointerLeave();
  virtual void onPointerMotion(float localX, float localY);
  virtual bool onPointerButton(std::uint32_t button, bool pressed);
  [[nodiscard]] virtual std::uint32_t cursorShape() const;

  [[nodiscard]] Node* root() const noexcept { return m_root ? m_root.get() : m_rootPtr; }
  [[nodiscard]] float width() const noexcept;
  [[nodiscard]] float height() const noexcept;

  std::unique_ptr<Node> releaseRoot();

  void setAnimationManager(AnimationManager* mgr) noexcept;
  void setRedrawCallback(RedrawCallback callback);
  void setContentScale(float scale) noexcept { m_contentScale = scale; }

protected:
  void requestRedraw();

  float m_contentScale = 1.0f;
  std::unique_ptr<Node> m_root;
  Node* m_rootPtr = nullptr;
  AnimationManager* m_animations = nullptr;
  RedrawCallback m_redrawCallback;
};
