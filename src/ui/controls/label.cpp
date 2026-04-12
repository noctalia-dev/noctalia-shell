#include "ui/controls/label.h"

#include "render/core/renderer.h"
#include "render/scene/text_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <memory>

Label::Label() {
  auto textNode = std::make_unique<TextNode>();
  m_textNode = static_cast<TextNode*>(addChild(std::move(textNode)));
  m_textNode->setFontSize(Style::fontSizeBody);
  applyPalette();
  m_paletteConn = paletteChanged().connect([this] { applyPalette(); });
}

void Label::setText(std::string_view text) { m_textNode->setText(std::string(text)); }

void Label::setFontSize(float size) { m_textNode->setFontSize(size); }

void Label::setColor(const ThemeColor& color) {
  m_color = color;
  applyPalette();
}

void Label::setColor(const Color& color) { setColor(fixedColor(color)); }

void Label::applyPalette() { m_textNode->setColor(resolveThemeColor(m_color)); }

void Label::setMinWidth(float minWidth) { m_minWidth = minWidth; }

void Label::setMaxWidth(float maxWidth) { m_textNode->setMaxWidth(maxWidth); }

void Label::setMaxLines(int maxLines) { m_textNode->setMaxLines(maxLines); }

void Label::setBold(bool bold) { m_textNode->setBold(bold); }

const std::string& Label::text() const noexcept { return m_textNode->text(); }

float Label::fontSize() const noexcept { return m_textNode->fontSize(); }

const Color& Label::color() const noexcept { return m_textNode->color(); }

float Label::maxWidth() const noexcept { return m_textNode->maxWidth(); }

bool Label::bold() const noexcept { return m_textNode->bold(); }

void Label::layout(Renderer& renderer) { measure(renderer); }

void Label::setCaptionStyle() {
  m_textNode->setFontSize(Style::fontSizeCaption);
  setColor(roleColor(ColorRole::OnSurface));
}

void Label::measure(Renderer& renderer) {
  const float maxWidth = m_textNode->maxWidth();
  const int maxLines = m_textNode->maxLines();
  const float assignedWidth = width();
  auto metrics = renderer.measureText(m_textNode->text(), m_textNode->fontSize(), m_textNode->bold(), maxWidth,
                                      maxLines);
  auto refMetrics = renderer.measureText("A", m_textNode->fontSize(), m_textNode->bold());
  const float measuredWidth = maxWidth > 0.0f ? std::min(metrics.width, maxWidth) : metrics.width;

  const float refHeight = refMetrics.bottom - refMetrics.top;
  const float actualHeight = metrics.bottom - metrics.top;
  // Keep single-line labels on a fixed "A"-based baseline.
  if (maxLines == 1) {
    m_baselineOffset = -refMetrics.top;
  } else {
    m_baselineOffset = -std::min(refMetrics.top, metrics.top);
  }
  const float inkBottom = m_baselineOffset + metrics.bottom;
  const float height = (maxLines == 1) ? refHeight : std::max({refHeight, actualHeight, inkBottom});
  const bool preserveAssignedWidth = flexGrow() > 0.0f && assignedWidth > 0.0f;
  const float finalWidth =
      preserveAssignedWidth ? std::max(assignedWidth, m_minWidth) : std::max(measuredWidth, m_minWidth);
  setSize(std::round(finalWidth), std::round(height));
  m_textNode->setPosition(0.0f, m_baselineOffset);
}
