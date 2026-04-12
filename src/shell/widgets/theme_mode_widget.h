#pragma once

#include "shell/widget/widget.h"

class Glyph;
class InputArea;

namespace noctalia::theme {
  class ThemeService;
}

class ThemeModeWidget : public Widget {
public:
  explicit ThemeModeWidget(noctalia::theme::ThemeService* themeService);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);

  noctalia::theme::ThemeService* m_themeService = nullptr;
  InputArea* m_area = nullptr;
  Glyph* m_glyph = nullptr;
  bool m_lastIsLight = false;
};

