#pragma once

#include "shell/widget/widget.h"

#include <cstdint>
#include <string>

class Label;
class TimeService;
struct wl_output;

class ClockWidget : public Widget {
public:
  ClockWidget(const TimeService& timeService, wl_output* output, std::string format = "{:%H:%M}");

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  const TimeService& m_time;
  wl_output* m_output = nullptr;
  std::string m_format;
  Label* m_label = nullptr;
  std::string m_lastText;
};
