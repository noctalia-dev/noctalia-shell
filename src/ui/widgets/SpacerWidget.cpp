#include "ui/widgets/SpacerWidget.hpp"

SpacerWidget::SpacerWidget(float width)
    : m_fixedWidth(width) {}

void SpacerWidget::create(Renderer& /*renderer*/) {
    m_root = std::make_unique<Node>();
    m_root->setSize(m_fixedWidth, 0.0f);
}

void SpacerWidget::layout(Renderer& /*renderer*/, float /*barWidth*/, float barHeight) {
    m_root->setSize(m_fixedWidth, barHeight);
}
