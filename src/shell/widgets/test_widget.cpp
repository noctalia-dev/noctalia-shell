#include "shell/widgets/test_widget.h"

#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/icon.h"
#include "ui/palette.h"

#include <memory>

TestWidget::TestWidget(wl_output* output, std::int32_t scale) : m_output(output), m_scale(scale) {}

void TestWidget::create(Renderer& renderer) {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    float absX = 0.0f;
    float absY = 0.0f;
    auto* node = root();
    if (node != nullptr) {
      Node::absolutePosition(node, absX, absY);
      absX += node->width() * 0.5f;
    }
    PanelManager::instance().togglePanel("test", m_output, m_scale, absX);
  });

  auto icon = std::make_unique<Icon>();
  icon->setIcon("flask");
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  area->addChild(std::move(icon));

  m_icon->measure(renderer);
  area->setSize(m_icon->width(), m_icon->height());

  m_root = std::move(area);
}

void TestWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  if (m_icon == nullptr) {
    return;
  }
  m_icon->measure(renderer);
  auto* node = root();
  if (node != nullptr) {
    node->setSize(m_icon->width(), m_icon->height());
  }
}
