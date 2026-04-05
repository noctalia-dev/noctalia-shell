#pragma once

#include "render/animation/animation_manager.h"
#include "render/core/color.h"
#include "render/scene/node.h"

class SpinnerNode;

class Spinner : public Node {
public:
  Spinner();

  void setColor(const Color& color);
  void setSpinnerSize(float size);
  void setThickness(float thickness);
  void setAnimationManager(AnimationManager* mgr) noexcept { m_animations = mgr; }

  void start();
  void stop();

  [[nodiscard]] bool spinning() const noexcept { return m_spinning; }

private:
  void startLoop();

  SpinnerNode* m_spinnerNode = nullptr;
  AnimationManager* m_animations = nullptr;
  AnimationManager::Id m_animId = 0;
  bool m_spinning = false;
};
