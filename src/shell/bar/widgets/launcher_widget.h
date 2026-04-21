#pragma once

#include "shell/bar/widget.h"

#include <cstdint>
#include <string>

class Glyph;
struct wl_output;

class LauncherWidget : public Widget {
public:
  LauncherWidget(wl_output* output, std::string barGlyphId);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  wl_output* m_output;
  std::string m_barGlyphId;
  Glyph* m_glyph = nullptr;
};
