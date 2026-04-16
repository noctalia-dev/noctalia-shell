#include "shell/widgets/clock_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "time/time_service.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

ClockWidget::ClockWidget(const TimeService& timeService, wl_output* output, std::string format)
    : m_time(timeService), m_output(output), m_format(std::move(format)) {}

std::string ClockWidget::formatTimeText() const {
  auto text = m_time.format(m_format.c_str());
  if (!m_isVertical) {
    return text;
  }

  for (char& c : text) {
    if (c == ':') {
      c = '\n';
    }
  }
  return text;
}

void ClockWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("control-center", m_output, 0.0f, 0.0f, "calendar");
  });

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setTextAlign(TextAlign::Center);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  m_label = label.get();
  area->addChild(std::move(label));
  setRoot(std::move(area));
}

void ClockWidget::doLayout(Renderer& renderer, float containerWidth, float containerHeight) {
  auto* rootNode = root();
  if (m_label == nullptr || rootNode == nullptr) {
    return;
  }
  m_isVertical = containerHeight > containerWidth;
  update(renderer);
  m_label->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_label->setMinWidth(0.0f);
  m_label->setMaxWidth(m_isVertical ? containerWidth : 0.0f);
  m_label->measure(renderer);
  m_label->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_label->width(), m_label->height());
}

void ClockWidget::doUpdate(Renderer& renderer) {
  auto text = formatTimeText();

  if (text != m_lastText) {
    m_lastText = std::move(text);
    m_label->setText(m_lastText);
    m_label->measure(renderer);
  }
}
