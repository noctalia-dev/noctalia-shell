#pragma once

#include "ui/Widget.hpp"

#include <string>

class Label;
class TimeService;

class ClockWidget : public Widget {
public:
    explicit ClockWidget(const TimeService& timeService);

    void create(Renderer& renderer) override;
    void layout(Renderer& renderer, float barWidth, float barHeight) override;
    void update(Renderer& renderer) override;

private:
    const TimeService& m_time;
    Label* m_label = nullptr;
    std::string m_lastText;
};
