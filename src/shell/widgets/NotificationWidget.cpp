#include "shell/widgets/NotificationWidget.hpp"

#include "ui/controls/Icon.hpp"

void NotificationWidget::create(Renderer& renderer) {
    auto icon = std::make_unique<Icon>();
    icon->setIcon("bell");
    m_icon = icon.get();
    m_root = std::move(icon);
    m_icon->measure(renderer);
}

void NotificationWidget::layout(Renderer& renderer, float /*barWidth*/, float /*barHeight*/) {
    m_icon->measure(renderer);
}
