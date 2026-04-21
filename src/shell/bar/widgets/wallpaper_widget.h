#pragma once

#include "shell/bar/widget.h"

#include <string>

class Glyph;
struct wl_output;

class WallpaperWidget : public Widget {
public:
  WallpaperWidget(wl_output* output, std::string barGlyphId);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  wl_output* m_output;
  std::string m_barGlyphId;
  Glyph* m_glyph = nullptr;
};
