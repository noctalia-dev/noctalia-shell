#include "shell/widgets/clock_widget.h"

#include "render/core/renderer.h"
#include "time/time_service.h"
#include "ui/controls/label.h"

ClockWidget::ClockWidget(const TimeService& timeService, std::string format)
    : m_time(timeService), m_format(std::move(format)) {}

void ClockWidget::create(Renderer& renderer) {
  auto label = std::make_unique<Label>();
  label->setCaptionStyle();
  m_label = label.get();
  m_root = std::move(label);
  update(renderer);
}

void ClockWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  m_label->measure(renderer);
}

void ClockWidget::update(Renderer& renderer) {
  auto text = m_time.format(m_format.c_str());

  if (text != m_lastText) {
    m_lastText = std::move(text);
    m_label->setText(m_lastText);
    m_label->measure(renderer);
  }
}
