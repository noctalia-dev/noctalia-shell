#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"
#include "ui/signal.h"

class RectNode;
class Renderer;

class Separator : public Node {
public:
  Separator();

  void setColor(const ThemeColor& color);
  void setThickness(float thickness);

protected:
  void doLayout(Renderer& renderer) override;

private:
  void applyPalette();

  RectNode* m_rect = nullptr;
  ThemeColor m_color = roleColor(ColorRole::Outline, 0.5f);
  float m_thickness = 1.0f;
  Signal<>::ScopedConnection m_paletteConn;
};
