#pragma once

#include "core/ui_phase.h"
#include "render/scene/node.h"

#include <functional>
#include <memory>

class AnimationManager;
class Renderer;

class DesktopWidget {
public:
  using RedrawCallback = std::function<void()>;

  virtual ~DesktopWidget() = default;

  virtual void create() = 0;

  void layout(Renderer& renderer) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    doLayout(renderer);
  }

  void update(Renderer& renderer) {
    UiPhaseScope updatePhase(UiPhase::Update);
    doUpdate(renderer);
  }

  [[nodiscard]] virtual bool wantsSecondTicks() const { return false; }
  [[nodiscard]] virtual bool needsFrameTick() const { return false; }
  virtual void onFrameTick(float deltaMs, Renderer& renderer) {
    (void)deltaMs;
    (void)renderer;
  }

  [[nodiscard]] Node* root() const noexcept { return m_root ? m_root.get() : m_rootPtr; }
  [[nodiscard]] float intrinsicWidth() const noexcept { return root() != nullptr ? root()->width() : 0.0f; }
  [[nodiscard]] float intrinsicHeight() const noexcept { return root() != nullptr ? root()->height() : 0.0f; }

  std::unique_ptr<Node> releaseRoot() {
    m_rootPtr = m_root.get();
    return std::move(m_root);
  }

  void setAnimationManager(AnimationManager* manager) noexcept { m_animations = manager; }
  void setRedrawCallback(RedrawCallback callback) { m_redrawCallback = std::move(callback); }
  void setContentScale(float scale) noexcept { m_contentScale = scale; }
  [[nodiscard]] float contentScale() const noexcept { return m_contentScale; }

protected:
  void setRoot(std::unique_ptr<Node> root) { m_root = std::move(root); }

  void requestRedraw() {
    if (m_redrawCallback) {
      m_redrawCallback();
    }
  }

  virtual void doLayout(Renderer& renderer) = 0;
  virtual void doUpdate(Renderer& renderer) { (void)renderer; }

  float m_contentScale = 1.0f;
  AnimationManager* m_animations = nullptr;

private:
  std::unique_ptr<Node> m_root;
  Node* m_rootPtr = nullptr;
  RedrawCallback m_redrawCallback;
};
