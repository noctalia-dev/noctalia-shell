#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

class SpinnerNode;

class Spinner : public Node {
public:
  Spinner();

  void setColor(const Color& color);
  void setSpinnerSize(float size);
  void setThickness(float thickness);

  void start();
  void stop();

  [[nodiscard]] bool spinning() const noexcept { return m_spinning; }

private:
  void startLoop();
  void updateGeometry();

  SpinnerNode* m_spinnerNode = nullptr;
  std::uint32_t m_animId = 0;
  bool m_spinning = false;
  float m_spinnerSize = 0.0f;
};
