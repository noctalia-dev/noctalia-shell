#pragma once

#include "shell/bar/widget.h"

#include <cstdint>

class Glyph;
struct wl_output;

class TestWidget : public Widget {
public:
  TestWidget(wl_output* output);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  wl_output* m_output;
  Glyph* m_glyph = nullptr;
};
