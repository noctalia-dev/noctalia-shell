#pragma once

#include "shell/widget/widget.h"

#include <cstdint>

class Glyph;
struct wl_output;

class SessionWidget : public Widget {
public:
  SessionWidget(wl_output* output);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  wl_output* m_output = nullptr;
  Glyph* m_glyph = nullptr;
};
