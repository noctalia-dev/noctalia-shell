#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"

#include <optional>

class RectNode;
struct CornerShapes;
struct Radii;
struct RectInsets;

// A styled rectangle that keeps its internal RectNode sized to match itself.
// Use this anywhere you need a background, separator, or decorative shape in
// shell/widget code — not RectNode directly.
class Box : public Node {
public:
  Box();

  void setFill(const ThemeColor& color);
  // Explicit fixed color.
  void setFill(const Color& color);
  void setBorder(const ThemeColor& color, float width);
  void setBorder(const Color& color, float width);
  void clearBorder();
  void setRadius(float radius);
  void setRadii(const Radii& radii);
  void setCornerShapes(const CornerShapes& corners);
  void setLogicalInset(const RectInsets& inset);
  void setSoftness(float softness);

  // Presets
  void setFlatStyle();
  void setCardStyle(float scale = 1.0f);
  void setPanelStyle();

  void setSize(float width, float height) override;
  void setFrameSize(float width, float height);

private:
  void applyPalette();

  RectNode* m_rect = nullptr;
  ThemeColor m_fill = clearThemeColor();
  ThemeColor m_border = clearThemeColor();
  float m_borderWidth = 0.0f;
  Signal<>::ScopedConnection m_paletteConn;
};
