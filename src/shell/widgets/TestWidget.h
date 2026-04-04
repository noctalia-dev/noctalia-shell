#pragma once

#include "shell/Widget.h"

class Toggle;

class TestWidget : public Widget {
public:
  TestWidget();

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  Toggle* m_toggle = nullptr;
};
