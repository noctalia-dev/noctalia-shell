#pragma once

#include "shell/widget/widget.h"

class SpacerWidget : public Widget {
public:
  explicit SpacerWidget(float width = 0.0f);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  float m_fixedWidth;
};
