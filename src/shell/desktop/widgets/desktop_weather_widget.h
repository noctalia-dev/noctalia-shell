#pragma once

#include "shell/desktop/desktop_widget.h"

#include <string>

class Glyph;
class Label;
class WeatherService;

class DesktopWeatherWidget : public DesktopWidget {
public:
  explicit DesktopWeatherWidget(const WeatherService* weather);

  void create() override;

private:
  void doLayout(Renderer& renderer) override;
  void doUpdate(Renderer& renderer) override;
  void sync(Renderer& renderer);

  const WeatherService* m_weather = nullptr;

  Glyph* m_glyph = nullptr;
  Label* m_temperature = nullptr;
  Label* m_condition = nullptr;

  std::string m_lastGlyph;
  std::string m_lastTemperature;
  std::string m_lastCondition;
};
