#pragma once

#include "shell/widget/widget.h"

class Glyph;
struct wl_output;

class WallpaperWidget : public Widget {
public:
  explicit WallpaperWidget(wl_output* output);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  wl_output* m_output;
  Glyph* m_glyph = nullptr;
};
