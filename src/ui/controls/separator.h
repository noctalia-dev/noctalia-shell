#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"
#include "ui/signal.h"

class RectNode;
class Renderer;

class Separator : public Node {
public:
  Separator();

  void setColor(const ColorSpec& color);
  void setThickness(float thickness);

protected:
  void doLayout(Renderer& renderer) override;

private:
  void applyPalette();

  RectNode* m_rectStart = nullptr;
  RectNode* m_rectEnd = nullptr;
  ColorSpec m_color = colorSpecFromRole(ColorRole::Outline);
  float m_thickness = 1.0f;
  Signal<>::ScopedConnection m_paletteConn;
};
