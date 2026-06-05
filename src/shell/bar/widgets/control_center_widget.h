#pragma once

#include "shell/bar/widget.h"

#include <cstdint>
#include <string>

class Glyph;
class Image;
struct wl_output;

class ControlCenterWidget : public Widget {
public:
  ControlCenterWidget(
      wl_output* output, std::string barGlyphId, std::string logoPath = "", bool customImageColorize = false
  );

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void refreshCustomImageTint();
  std::string m_barGlyphId;
  std::string m_logoPath;
  bool m_customImageColorize = false;
  Glyph* m_glyph = nullptr;
  Image* m_image = nullptr;
};
