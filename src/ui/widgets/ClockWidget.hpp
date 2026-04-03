#pragma once

#include "ui/Widget.hpp"

class Label;

class ClockWidget : public Widget {
public:
    void create(Renderer& renderer) override;
    void layout(Renderer& renderer, float barWidth, float barHeight) override;
    void update(Renderer& renderer) override;

private:
    Label* m_label = nullptr;
    std::string m_lastText;
};
