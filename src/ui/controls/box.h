#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

class RectNode;

// A styled rectangle that keeps its internal RectNode sized to match itself.
// Use this anywhere you need a background, separator, or decorative shape in
// shell/widget code — not RectNode directly.
class Box : public Node {
public:
  Box();

  void setFill(const Color& color);
  void setBorder(const Color& color, float width);
  void setRadius(float radius);
  void setSoftness(float softness);

  // Presets
  void setFlatStyle();
  void setCardStyle();
  void setPanelStyle();

  void setSize(float width, float height) override;

private:
  RectNode* m_rect = nullptr;
};
