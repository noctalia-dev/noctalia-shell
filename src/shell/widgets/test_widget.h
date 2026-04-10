#pragma once

#include "shell/widget/widget.h"

#include <cstdint>

class Glyph;
struct wl_output;

class TestWidget : public Widget {
public:
  TestWidget(wl_output* output);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  wl_output* m_output;
  Glyph* m_glyph = nullptr;
};
