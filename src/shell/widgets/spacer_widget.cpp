#include "shell/widgets/spacer_widget.h"

#include "render/scene/node.h"

SpacerWidget::SpacerWidget(float length) : m_fixedLength(length) {}

void SpacerWidget::create() {
  auto spacer = std::make_unique<Node>();
  spacer->setSize(0.0f, 0.0f);
  setRoot(std::move(spacer));
}

void SpacerWidget::doLayout(Renderer& /*renderer*/, float containerWidth, float containerHeight) {
  if (root() != nullptr) {
    const float length = m_fixedLength * m_contentScale;
    const bool isVertical = containerHeight > containerWidth;
    root()->setSize(isVertical ? 0.0f : length, isVertical ? length : 0.0f);
  }
}
