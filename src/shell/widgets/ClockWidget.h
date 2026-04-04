#pragma once

#include "shell/Widget.h"

#include <string>

class Label;
class TimeService;

class ClockWidget : public Widget {
public:
    ClockWidget(const TimeService& timeService, std::string format = "{:%H:%M}");

    void create(Renderer& renderer) override;
    void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
    void update(Renderer& renderer) override;

private:
    const TimeService& m_time;
    std::string m_format;
    Label* m_label = nullptr;
    std::string m_lastText;
};
