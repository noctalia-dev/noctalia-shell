#include "ui/controls/label.h"

#include "render/core/renderer.h"
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

void Label::setText(std::string_view text) {
  if (m_textNode->text() == text) {
    return;
  }
  m_textNode->setText(std::string(text));
  m_measureCached = false;
}

void Label::setFontSize(float size) {
  if (m_textNode->fontSize() == size) {
    return;
  }
  m_textNode->setFontSize(size);
  m_measureCached = false;
}

void Label::setColor(const ThemeColor& color) {
  m_color = color;
  applyPalette();
}

void Label::setColor(const Color& color) { setColor(fixedColor(color)); }

void Label::applyPalette() { m_textNode->setColor(resolveThemeColor(m_color)); }

void Label::setMinWidth(float minWidth) {
  if (m_minWidth == minWidth) {
    return;
  }
  m_minWidth = minWidth;
  m_measureCached = false;
}

void Label::setMaxWidth(float maxWidth) {
  if (m_textNode->maxWidth() == maxWidth) {
    return;
  }
  m_textNode->setMaxWidth(maxWidth);
  m_measureCached = false;
}

void Label::setMaxLines(int maxLines) {
  if (m_textNode->maxLines() == maxLines) {
    return;
  }
  m_textNode->setMaxLines(maxLines);
  m_measureCached = false;
}

void Label::setBold(bool bold) {
  if (m_textNode->bold() == bold) {
    return;
  }
  m_textNode->setBold(bold);
  m_measureCached = false;
}

const std::string& Label::text() const noexcept { return m_textNode->text(); }

float Label::fontSize() const noexcept { return m_textNode->fontSize(); }

const Color& Label::color() const noexcept { return m_textNode->color(); }

float Label::maxWidth() const noexcept { return m_textNode->maxWidth(); }

bool Label::bold() const noexcept { return m_textNode->bold(); }

TextAlign Label::textAlign() const noexcept { return m_textNode->textAlign(); }

void Label::setTextAlign(TextAlign align) {
  if (m_textNode->textAlign() == align) {
    return;
  }
  m_textNode->setTextAlign(align);
  m_measureCached = false;
}

void Label::doLayout(Renderer& renderer) { measure(renderer); }

void Label::setCaptionStyle() {
  setFontSize(Style::fontSizeCaption);
  setColor(roleColor(ColorRole::OnSurface));
}

void Label::measure(Renderer& renderer) {
  const float maxWidth = m_textNode->maxWidth();
  const int maxLines = m_textNode->maxLines();
  const bool singleLine =
      (maxLines == 1) || (maxLines == 0 && maxWidth <= 0.0f && m_textNode->text().find('\n') == std::string::npos);
  const float assignedWidth = width();
  const float curFlexGrow = flexGrow();
  const TextAlign align = m_textNode->textAlign();
  if (m_measureCached && m_cachedText == m_textNode->text() && m_cachedFontSize == m_textNode->fontSize() &&
      m_cachedBold == m_textNode->bold() && m_cachedMaxWidth == maxWidth && m_cachedMaxLines == maxLines &&
      m_cachedMinWidth == m_minWidth && m_cachedAssignedWidth == assignedWidth && m_cachedFlexGrow == curFlexGrow &&
      m_cachedTextAlign == align) {
    return;
  }
  auto metrics = renderer.measureText(m_textNode->text(), m_textNode->fontSize(), m_textNode->bold(), maxWidth,
                                      maxLines, align);
  auto refMetrics = renderer.measureText("A", m_textNode->fontSize(), m_textNode->bold());
  const float measuredWidth = maxWidth > 0.0f ? std::min(metrics.width, maxWidth) : metrics.width;

  const float refHeight = refMetrics.bottom - refMetrics.top;
  const float actualHeight = metrics.bottom - metrics.top;
  const float inkHeight = std::max(0.0f, metrics.inkBottom - metrics.inkTop);
  // Keep single-line labels on the same reference height as glyphs, but center
  // the visible text ink within that height so digits and symbols do not read
  // optically low beside icons.
  if (singleLine && inkHeight > 0.0f) {
    const float slotHeight = std::max(1.0f, Style::toOdd(std::max(refHeight, inkHeight)));
    m_baselineOffset = Style::pixelAlignCenter(slotHeight, inkHeight) - metrics.inkTop;
    setSize(std::round(std::max(measuredWidth, m_minWidth)), slotHeight);
  } else {
    m_baselineOffset = -std::min(refMetrics.top, metrics.top);
    const float inkBottom = m_baselineOffset + metrics.bottom;
    const float height = std::max({refHeight, actualHeight, inkBottom});
    const bool preserveAssignedWidth = flexGrow() > 0.0f && assignedWidth > 0.0f;
    const float finalWidth =
        preserveAssignedWidth ? std::max(assignedWidth, m_minWidth) : std::max(measuredWidth, m_minWidth);
    setSize(std::round(finalWidth), std::round(height));
  }
  m_visualTop = m_baselineOffset + metrics.inkTop;
  m_visualBottom = m_baselineOffset + metrics.inkBottom;
  const bool preserveAssignedWidth = flexGrow() > 0.0f && assignedWidth > 0.0f;
  if (preserveAssignedWidth) {
    setSize(std::round(std::max(assignedWidth, m_minWidth)), height());
  } else if (width() < m_minWidth) {
    setSize(std::round(m_minWidth), height());
  }
  float textX = 0.0f;
  const float finalWidth = width();
  if (align == TextAlign::Center) {
    textX = (finalWidth - measuredWidth) * 0.5f;
  } else if (align == TextAlign::End) {
    textX = finalWidth - measuredWidth;
  }
  // Keep subpixel baseline/text offsets here; cairo text rendering performs
  // a single final snap in device-pixel space after full world transform.
  m_textNode->setPosition(textX, m_baselineOffset);

  m_cachedText = m_textNode->text();
  m_cachedFontSize = m_textNode->fontSize();
  m_cachedBold = m_textNode->bold();
  m_cachedMaxWidth = maxWidth;
  m_cachedMaxLines = maxLines;
  m_cachedMinWidth = m_minWidth;
  m_cachedAssignedWidth = assignedWidth;
  m_cachedFlexGrow = curFlexGrow;
  m_cachedTextAlign = align;
  m_measureCached = true;
}
