#pragma once

#include "shell/Widget.hpp"

class SpacerWidget : public Widget {
public:
    explicit SpacerWidget(float width = 0.0f);

    void create(Renderer& renderer) override;
    void layout(Renderer& renderer, float barWidth, float barHeight) override;

private:
    float m_fixedWidth;
};
