#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"
#include "ui/signal.h"

#include <cstdint>

class RectNode;
class Renderer;

enum class SeparatorOrientation : std::uint8_t {
  // Infer from parent: horizontal rule inside a vertical Flex, vertical rule inside a horizontal Flex.
  Auto,
  HorizontalRule,
  VerticalRule,
};

class Separator : public Node {
public:
  Separator();

  void setColor(const ColorSpec& color);
  void setThickness(float thickness);
  void setOrientation(SeparatorOrientation orientation);

protected:
  LayoutSize doMeasure(Renderer& renderer, const LayoutConstraints& constraints) override;
  void doLayout(Renderer& renderer) override;

private:
  [[nodiscard]] bool ruleIsHorizontal() const;
  void applyPalette();

  RectNode* m_rectStart = nullptr;
  RectNode* m_rectEnd = nullptr;
  ColorSpec m_color = colorSpecFromRole(ColorRole::Outline);
  float m_thickness = 1.0f;
  SeparatorOrientation m_orientation = SeparatorOrientation::Auto;
  Signal<>::ScopedConnection m_paletteConn;
};
