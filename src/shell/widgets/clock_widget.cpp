#include "shell/widgets/clock_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "time/time_service.h"
#include "ui/controls/label.h"
#include "ui/style.h"

ClockWidget::ClockWidget(const TimeService& timeService, wl_output* output, std::int32_t scale, std::string format)
    : m_time(timeService), m_output(output), m_scale(scale), m_format(std::move(format)) {}

void ClockWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    float absX = 0.0f;
    float absY = 0.0f;
    // auto* node = root();
    // if (node != nullptr) {
    //   Node::absolutePosition(node, absX, absY);
    //   absX += node->width() * 0.5f;
    //   absY += node->height() * 0.5f;
    // }
    PanelManager::instance().togglePanel("control-center", m_output, m_scale, absX, absY, "calendar");
  });

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  m_label = label.get();
  area->addChild(std::move(label));
  setRoot(std::move(area));
}

void ClockWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_label == nullptr || rootNode == nullptr) {
    return;
  }
  update(renderer);
  m_label->measure(renderer);
  m_label->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_label->width(), m_label->height());
}

void ClockWidget::update(Renderer& renderer) {
  auto text = m_time.format(m_format.c_str());

  if (text != m_lastText) {
    m_lastText = std::move(text);
    m_label->setText(m_lastText);
    m_label->measure(renderer);
  }
}
