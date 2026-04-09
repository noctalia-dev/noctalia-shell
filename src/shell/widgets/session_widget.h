#pragma once

#include "shell/widget/widget.h"

#include <cstdint>

class Glyph;
struct wl_output;

class SessionWidget : public Widget {
public:
  SessionWidget(wl_output* output, std::int32_t scale);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  wl_output* m_output = nullptr;
  std::int32_t m_scale = 1;
  Glyph* m_glyph = nullptr;
};
