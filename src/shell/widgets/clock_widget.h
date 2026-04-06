#pragma once

#include "shell/widget/widget.h"

#include <cstdint>
#include <string>

class Label;
class TimeService;
struct wl_output;

class ClockWidget : public Widget {
public:
  ClockWidget(const TimeService& timeService, wl_output* output, std::int32_t scale,
              std::string format = "{:%H:%M}");

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  const TimeService& m_time;
  wl_output* m_output = nullptr;
  std::int32_t m_scale = 1;
  std::string m_format;
  Label* m_label = nullptr;
  std::string m_lastText;
};
