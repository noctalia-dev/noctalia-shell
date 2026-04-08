#pragma once

#include "shell/widget/widget.h"

#include <cstdint>
#include <string>

class Glyph;
class InputArea;
class Label;
class Renderer;
class WeatherService;
struct wl_output;

class WeatherWidget : public Widget {
public:
  WeatherWidget(WeatherService* weather, wl_output* output, std::int32_t scale, float maxWidth, bool showCondition);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void sync(Renderer& renderer);

  WeatherService* m_weather = nullptr;
  wl_output* m_output = nullptr;
  std::int32_t m_scale = 1;
  float m_maxWidth = 160.0f;
  bool m_showCondition = true;
  InputArea* m_area = nullptr;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  std::string m_lastText;
  std::string m_lastGlyph;
};
