#pragma once

#include "config/config_service.h"
#include "shell/desktop/desktop_widget.h"

#include <memory>
#include <string>
#include <unordered_map>

class TimeService;
class PipeWireSpectrum;
class WeatherService;

class DesktopWidgetFactory {
public:
  DesktopWidgetFactory(TimeService* timeService, PipeWireSpectrum* pipewireSpectrum, const WeatherService* weather);

  [[nodiscard]] std::unique_ptr<DesktopWidget>
  create(const std::string& type, const std::unordered_map<std::string, WidgetSettingValue>& settings,
         float contentScale = 1.0f) const;

private:
  TimeService* m_timeService = nullptr;
  PipeWireSpectrum* m_pipewireSpectrum = nullptr;
  const WeatherService* m_weather = nullptr;
};
