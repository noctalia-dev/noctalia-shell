#pragma once

#include "shell/bar/widget.h"
#include "shell/bar/widget_custom_image.h"

#include <string>

class Glyph;
class Image;
struct wl_output;

class WallpaperWidget : public Widget {
public:
  WallpaperWidget(wl_output* output, std::string barGlyphId, WidgetCustomImage customImage = {});

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  std::string m_barGlyphId;
  WidgetCustomImage m_customImage;
  Glyph* m_glyph = nullptr;
  Image* m_image = nullptr;
};
