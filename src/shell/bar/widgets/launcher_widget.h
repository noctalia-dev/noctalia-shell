#pragma once

#include "shell/bar/widget.h"

#include <cstdint>
#include <string>

class Glyph;
class Image;
struct wl_output;

class LauncherWidget : public Widget {
public:
  LauncherWidget(wl_output* output, std::string barGlyphId, std::string logoPath = "");

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  wl_output* m_output;
  std::string m_barGlyphId;
  std::string m_logoPath;
  Glyph* m_glyph = nullptr;
  Image* m_image = nullptr;
};
