#include "shell/widgets/TestWidget.h"

#include "render/scene/InputArea.h"
#include "ui/controls/Toggle.h"

#include <memory>

TestWidget::TestWidget() = default;

void TestWidget::create(Renderer& /*renderer*/) {
  auto area = std::make_unique<InputArea>();
  area->setCursorShape(1); // pointer cursor
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    m_toggle->setChecked(!m_toggle->checked());
  });

  auto toggle = std::make_unique<Toggle>();
  toggle->setToggleSize(ToggleSize::Small);
  toggle->setChecked(false);
  m_toggle = toggle.get();
  area->addChild(std::move(toggle));

  m_root = std::move(area);
}

void TestWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_toggle == nullptr) {
    return;
  }
  m_toggle->layout(renderer);
  auto* node = root();
  if (node != nullptr) {
    node->setSize(m_toggle->width(), m_toggle->height());
  }
}
