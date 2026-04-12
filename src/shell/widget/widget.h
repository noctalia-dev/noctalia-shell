#pragma once

#include "core/ui_phase.h"
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
  void layout(Renderer& renderer, float containerWidth, float containerHeight) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    doLayout(renderer, containerWidth, containerHeight);
  }
  void update(Renderer& renderer) {
    UiPhaseScope updatePhase(UiPhase::Update);
    doUpdate(renderer);
  }
  virtual void onFrameTick(float deltaMs) { (void)deltaMs; }
  [[nodiscard]] virtual bool needsFrameTick() const { return false; }

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
  void setRoot(std::unique_ptr<Node> root) { m_root = std::move(root); }
  void clearReleasedRoot() noexcept { m_rootPtr = nullptr; }
  virtual void doLayout(Renderer& renderer, float containerWidth, float containerHeight) = 0;
  virtual void doUpdate(Renderer& renderer) { (void)renderer; }

  float m_contentScale = 1.0f;
  AnimationManager* m_animations = nullptr;
  RedrawCallback m_redrawCallback;

private:
  std::unique_ptr<Node> m_root;
  Node* m_rootPtr = nullptr;
};
