#pragma once

#include "shell/widget/widget.h"

#include <cstdint>

class Glyph;
struct wl_output;

class LauncherWidget : public Widget {
public:
  LauncherWidget(wl_output* output, std::int32_t scale);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  wl_output* m_output;
  std::int32_t m_scale;
  Glyph* m_glyph = nullptr;
};
