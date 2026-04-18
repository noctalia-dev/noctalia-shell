#include "shell/desktop/widgets/desktop_clock_widget.h"

#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "time/time_service.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

namespace {

  bool formatShowsSeconds(const std::string& format) {
    return format.find("%S") != std::string::npos || format.find("%T") != std::string::npos ||
           format.find("%X") != std::string::npos;
  }

} // namespace

DesktopClockWidget::DesktopClockWidget(const TimeService& timeService, std::string format)
    : m_timeService(timeService), m_format(std::move(format)), m_showsSeconds(formatShowsSeconds(m_format)) {}

void DesktopClockWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setTextAlign(TextAlign::Center);
  label->setStableBaseline(true);
  label->setColor(roleColor(ColorRole::OnSurface));
  label->setFontSize(Style::fontSizeBody * 4.0f * m_contentScale);
  m_label = label.get();

  rootNode->addChild(std::move(label));
  setRoot(std::move(rootNode));
}

bool DesktopClockWidget::wantsSecondTicks() const { return m_showsSeconds; }

std::string DesktopClockWidget::formatText() const { return m_timeService.format(m_format.c_str()); }

void DesktopClockWidget::doLayout(Renderer& renderer) {
  if (m_label == nullptr || root() == nullptr) {
    return;
  }

  update(renderer);
  m_label->measure(renderer);
  m_label->setPosition(0.0f, 0.0f);
  root()->setSize(m_label->width(), m_label->height());
}

void DesktopClockWidget::doUpdate(Renderer& renderer) {
  if (m_label == nullptr) {
    return;
  }

  const std::string text = formatText();
  if (text == m_lastText) {
    return;
  }

  m_lastText = text;
  m_label->setText(m_lastText);
  m_label->measure(renderer);
}
