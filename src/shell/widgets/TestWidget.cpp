#include "shell/widgets/TestWidget.h"

#include "render/scene/InputArea.h"
#include "render/scene/Node.h"
#include "ui/controls/Icon.h"
#include "ui/style/Palette.h"

#include <memory>

TestWidget::TestWidget(wl_output* output, std::int32_t scale, PanelRequestCallback callback)
    : m_output(output), m_scale(scale), m_panelCallback(std::move(callback)) {}

void TestWidget::create(Renderer& renderer) {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    if (m_panelCallback) {
      // Compute absolute X from the widget's position in the scene
      float absX = 0.0f;
      float absY = 0.0f;
      auto* node = root();
      if (node != nullptr) {
        Node::absolutePosition(node, absX, absY);
        absX += node->width() * 0.5f;
      }
      m_panelCallback("test", m_output, m_scale, absX);
    }
  });

  auto icon = std::make_unique<Icon>();
  icon->setIcon("settings");
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
