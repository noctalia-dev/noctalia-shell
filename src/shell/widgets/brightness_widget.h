#pragma once

#include "shell/widget/widget.h"

class BrightnessService;
class Glyph;
class Label;
struct wl_output;

class BrightnessWidget : public Widget {
public:
  BrightnessWidget(BrightnessService* brightness, wl_output* output);

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);

  BrightnessService* m_brightness = nullptr;
  wl_output* m_output = nullptr;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  bool m_lastAvailable = false;
  float m_lastBrightness = -1.0f;
};
