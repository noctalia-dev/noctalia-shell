#include "shell/widgets/spacer_widget.h"

#include "render/scene/node.h"

SpacerWidget::SpacerWidget(float length) : m_fixedLength(length) {}

void SpacerWidget::create() {
  auto spacer = std::make_unique<Node>();
  spacer->setSize(m_fixedLength * m_contentScale, 0.0f);
  setRoot(std::move(spacer));
}

void SpacerWidget::layout(Renderer& /*renderer*/, float /*containerWidth*/, float containerHeight) {
  if (root() != nullptr) {
    root()->setSize(m_fixedLength * m_contentScale, containerHeight);
  }
}
