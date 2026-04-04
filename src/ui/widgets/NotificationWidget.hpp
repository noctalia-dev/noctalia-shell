#pragma once

#include "ui/Widget.hpp"

class Icon;

class NotificationWidget : public Widget {
public:
    void create(Renderer& renderer) override;
    void layout(Renderer& renderer, float barWidth, float barHeight) override;

private:
    Icon* m_icon = nullptr;
};
