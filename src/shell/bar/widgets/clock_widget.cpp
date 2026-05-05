#include "shell/bar/widgets/clock_widget.h"

#include "render/core/renderer.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "time/time_format.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

ClockWidget::ClockWidget(wl_output* output, std::string format, std::string verticalFormat)
    : m_output(output), m_format(std::move(format)), m_verticalFormat(std::move(verticalFormat)) {}

std::string ClockWidget::formatTimeText() const {
  if (!m_isVertical) {
    return formatLocalTime(m_format.c_str());
  }

  if (!m_verticalFormat.empty()) {
    return formatLocalTime(m_verticalFormat.c_str());
  }

  // Fallback for vertical bars when no explicit vertical_format is configured:
  // stack each whitespace- or colon-separated token on its own line so "21:15"
  // splits into "21" / "15". Matches Pango's lineBudget (1 + '\n' count) so
  // nothing gets ellipsized unless a single token is wider than the bar.
  auto text = formatLocalTime(m_format.c_str());
  std::string out;
  out.reserve(text.size());
  bool lastWasBreak = true;
  for (char c : text) {
    const bool isBreak = (c == ' ' || c == '\t' || c == ':');
    if (isBreak) {
      if (!lastWasBreak) {
        out.push_back('\n');
        lastWasBreak = true;
      }
    } else {
      out.push_back(c);
      lastWasBreak = false;
    }
  }
  if (!out.empty() && out.back() == '\n') {
    out.pop_back();
  }
  return out;
}

void ClockWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick(
      [this](const InputArea::PointerData& /*data*/) { requestPanelToggle("control-center", "calendar"); });

  auto label = std::make_unique<Label>();
  label->setBold(true);
  label->setTextAlign(TextAlign::Center);
  label->setFontSize(Style::fontSizeBody * m_contentScale);
  // Clock text changes every minute and month names switch between descender
  // and descender-less forms (e.g. "Mar" ↔ "Apr"), so anchor the baseline to
  // a stable ink envelope instead of the current text's ink.
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
  m_label->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  // Horizontal clocks should use single-line metrics so capsule height matches sibling widgets.
  m_label->setMaxLines(m_isVertical ? 0 : 1);
  m_label->setMinWidth(0.0f);
  m_label->setMaxWidth(m_isVertical ? containerWidth : 0.0f);
  m_label->measure(renderer);
  m_label->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_label->width(), m_label->height());
}

void ClockWidget::doUpdate(Renderer& renderer) {
  if (m_label == nullptr) {
    return;
  }

  auto text = formatTimeText();

  if (text != m_lastText) {
    m_lastText = std::move(text);
    m_label->setText(m_lastText);
    m_label->measure(renderer);
  }
}
