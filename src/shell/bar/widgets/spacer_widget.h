#pragma once

#include "shell/bar/widget.h"

class SpacerWidget : public Widget {
public:
  explicit SpacerWidget(float length = 0.0f);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  float m_fixedLength;
};
