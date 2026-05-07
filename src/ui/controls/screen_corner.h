#pragma once

#include "render/core/color.h"
#include "render/core/render_styles.h"
#include "render/scene/node.h"

class ScreenCornerNode;

class ScreenCorner : public Node {
public:
  ScreenCorner();

  void setColor(const Color& color);
  void setCorner(ScreenCornerPosition position);
  void setExponent(float exponent);
  void setSoftness(float softness);

  void setSize(float width, float height) override;
  void setFrameSize(float width, float height);

private:
  ScreenCornerNode* m_corner = nullptr;
};
