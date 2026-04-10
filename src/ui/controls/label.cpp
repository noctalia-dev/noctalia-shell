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
  m_textNode->setColor(palette.onSurface);
}

void Label::setText(std::string_view text) { m_textNode->setText(std::string(text)); }

void Label::setFontSize(float size) { m_textNode->setFontSize(size); }

void Label::setColor(const Color& color) { m_textNode->setColor(color); }

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
  m_textNode->setColor(palette.onSurface);
}

void Label::measure(Renderer& renderer) {
  const float maxWidth = m_textNode->maxWidth();
  const int maxLines = m_textNode->maxLines();
  auto metrics = renderer.measureText(m_textNode->text(), m_textNode->fontSize(), m_textNode->bold(), maxWidth,
                                      maxLines);
  auto refMetrics = renderer.measureText("A", m_textNode->fontSize(), m_textNode->bold());
  const float measuredWidth = maxWidth > 0.0f ? std::min(metrics.width, maxWidth) : metrics.width;

  // Use "A" (cap-height + SDF top/bottom padding, no descender) as the reference
  // bounding box for the *first* line — this keeps single-line labels of the
  // same font size at a consistent height, and places the digit/letter ink
  // center at the geometric center of the bounding box (optical centering in
  // bars/controls). For wrapped multi-line text we grow the box to the
  // actual Pango-rendered height so the container reserves enough room.
  m_baselineOffset = -refMetrics.top;
  const float refHeight = refMetrics.bottom - refMetrics.top;
  const float actualHeight = metrics.bottom - metrics.top;
  const float height = std::max(refHeight, actualHeight);
  setSize(std::round(std::max(measuredWidth, m_minWidth)), std::round(height));
  m_textNode->setPosition(0.0f, m_baselineOffset);
}
