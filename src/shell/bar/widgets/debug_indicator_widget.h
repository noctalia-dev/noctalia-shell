#pragma once

#ifndef NDEBUG

#include "shell/bar/widget.h"

class Chip;
class Renderer;

class DebugIndicatorWidget : public Widget {
public:
  DebugIndicatorWidget();

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;

  Chip* m_chip = nullptr;
};

#endif
