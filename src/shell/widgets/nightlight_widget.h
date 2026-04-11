#pragma once

#include "shell/widget/widget.h"

class Glyph;
class InputArea;
class NightLightManager;

class NightLightWidget : public Widget {
public:
  explicit NightLightWidget(NightLightManager* nightLight);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);

  NightLightManager* m_nightLight = nullptr;
  InputArea* m_area = nullptr;
  Glyph* m_glyph = nullptr;
  bool m_lastEnabled = false;
  bool m_lastActive = false;
  bool m_lastForced = false;
};
