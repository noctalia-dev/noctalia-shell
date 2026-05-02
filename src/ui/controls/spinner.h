#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"
#include "ui/palette.h"
#include "ui/signal.h"

#include <optional>

class SpinnerNode;

class Spinner : public Node {
public:
  Spinner();

  void setColor(const ColorSpec& color);
  void setColor(const Color& color);
  void setSpinnerSize(float size);
  void setThickness(float thickness);

  void start();
  void stop();

  [[nodiscard]] bool spinning() const noexcept { return m_spinning; }

private:
  void applyPalette();
  void startLoop();
  void updateGeometry();

  SpinnerNode* m_spinnerNode = nullptr;
  ColorSpec m_color = colorSpecFromRole(ColorRole::Primary);
  Signal<>::ScopedConnection m_paletteConn;
  std::uint32_t m_animId = 0;
  bool m_spinning = false;
  float m_spinnerSize = 0.0f;
};
