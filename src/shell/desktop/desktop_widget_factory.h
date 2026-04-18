#pragma once

#include "config/config_service.h"
#include "shell/desktop/desktop_widget.h"

#include <memory>
#include <string>
#include <unordered_map>

class TimeService;
class PipeWireSpectrum;

class DesktopWidgetFactory {
public:
  DesktopWidgetFactory(TimeService* timeService, PipeWireSpectrum* pipewireSpectrum);

  [[nodiscard]] std::unique_ptr<DesktopWidget>
  create(const std::string& type, const std::unordered_map<std::string, WidgetSettingValue>& settings,
         float contentScale = 1.0f) const;

private:
  TimeService* m_timeService = nullptr;
  PipeWireSpectrum* m_pipewireSpectrum = nullptr;
};
