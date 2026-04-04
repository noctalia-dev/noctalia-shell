#include "shell/panels/TestPanelContent.h"

#include "render/scene/InputArea.h"
#include "ui/controls/Box.h"
#include "ui/controls/Label.h"
#include "ui/controls/Toggle.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

#include <memory>

void TestPanelContent::create(Renderer& renderer) {
  auto container = std::make_unique<Box>();
  container->setDirection(BoxDirection::Horizontal);
  container->setGap(Style::spaceMd);
  container->setAlign(BoxAlign::Center);

  auto label = std::make_unique<Label>();
  label->setText("Test Toggle");
  label->setFontSize(Style::fontSizeSm);
  label->setColor(palette.onSurface);
  m_label = label.get();
  container->addChild(std::move(label));

  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    m_toggle->setChecked(!m_toggle->checked());
  });

  auto toggle = std::make_unique<Toggle>();
  toggle->setToggleSize(ToggleSize::Medium);
  toggle->setChecked(false);
  toggle->setAnimationManager(m_animations);
  m_toggle = toggle.get();
  area->addChild(std::move(toggle));

  m_container = container.get();
  container->addChild(std::move(area));

  m_root = std::move(container);

  // Measure label so Box::layout can compute sizes
  m_label->measure(renderer);
}

void TestPanelContent::layout(Renderer& renderer, float /*width*/, float /*height*/) {
  if (m_container == nullptr) {
    return;
  }
  if (m_label != nullptr) {
    m_label->measure(renderer);
  }
  if (m_toggle != nullptr) {
    m_toggle->layout(renderer);
  }
  // Size the InputArea to match the toggle
  if (m_toggle != nullptr && m_toggle->parent() != nullptr) {
    m_toggle->parent()->setSize(m_toggle->width(), m_toggle->height());
  }
  m_container->layout(renderer);
}

void TestPanelContent::update(Renderer& /*renderer*/) {}
