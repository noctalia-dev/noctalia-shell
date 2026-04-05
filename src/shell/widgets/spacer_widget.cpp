#include "shell/widgets/spacer_widget.h"

#include "ui/controls/flex.h"

SpacerWidget::SpacerWidget(float width) : m_fixedWidth(width) {}

void SpacerWidget::create(Renderer& /*renderer*/) {
  auto box = std::make_unique<Flex>();
  box->setSize(m_fixedWidth, 0.0f);
  m_root = std::unique_ptr<Node>(box.release());
}

void SpacerWidget::layout(Renderer& /*renderer*/, float /*containerWidth*/, float containerHeight) {
  m_root->setSize(m_fixedWidth, containerHeight);
}
