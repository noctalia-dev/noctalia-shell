#pragma once

#include "ui/Widget.hpp"

#include <string>

class Label;
class TimeService;

class ClockWidget : public Widget {
public:
    ClockWidget(const TimeService& timeService, std::string format = "{:%H:%M}");

    void create(Renderer& renderer) override;
    void layout(Renderer& renderer, float barWidth, float barHeight) override;
    void update(Renderer& renderer) override;

private:
    const TimeService& m_time;
    std::string m_format;
    Label* m_label = nullptr;
    std::string m_lastText;
};
