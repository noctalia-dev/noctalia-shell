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

bool Label::setText(std::string_view text) {
  if (m_textNode->text() == text)
    return false;
  m_textNode->setText(std::string(text));
  m_measureCached = false;
  return true;
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

void Label::setStableBaseline(bool stable) {
  if (m_stableBaseline == stable) {
    return;
  }
  m_stableBaseline = stable;
  m_measureCached = false;
}

void Label::setShadow(const Color& color, float offsetX, float offsetY) {
  m_textNode->setShadow(color, offsetX, offsetY);
}

void Label::clearShadow() { m_textNode->clearShadow(); }

void Label::doLayout(Renderer& renderer) { measure(renderer); }

LayoutSize Label::doMeasure(Renderer& renderer, const LayoutConstraints& constraints) {
  return measureWithConstraints(renderer, constraints);
}

void Label::doArrange(Renderer& renderer, const LayoutRect& rect) {
  setPosition(rect.x, rect.y);
  LayoutConstraints constraints;
  constraints.setExactWidth(rect.width);
  const LayoutSize measured = measureWithConstraints(renderer, constraints);
  setSize(rect.width, rect.height > 0.0f ? rect.height : measured.height);
}

void Label::setCaptionStyle() {
  setFontSize(Style::fontSizeCaption);
  setColor(roleColor(ColorRole::OnSurface));
}

void Label::measure(Renderer& renderer) {
  LayoutConstraints constraints;
  measureWithConstraints(renderer, constraints);
}

LayoutSize Label::measureWithConstraints(Renderer& renderer, const LayoutConstraints& constraints) {
  const float configuredMaxWidth = m_textNode->maxWidth();
  float measureMaxWidth = configuredMaxWidth;
  if (constraints.hasMaxWidth) {
    measureMaxWidth =
        configuredMaxWidth > 0.0f ? std::min(configuredMaxWidth, constraints.maxWidth) : constraints.maxWidth;
  }
  const int maxLines = m_textNode->maxLines();
  const bool singleLine = (maxLines == 1) || (maxLines == 0 && configuredMaxWidth <= 0.0f &&
                                              m_textNode->text().find('\n') == std::string::npos);
  const TextAlign align = m_textNode->textAlign();
  if (m_measureCached && m_cachedText == m_textNode->text() && m_cachedFontSize == m_textNode->fontSize() &&
      m_cachedBold == m_textNode->bold() && m_cachedMaxWidth == configuredMaxWidth && m_cachedMaxLines == maxLines &&
      m_cachedMinWidth == m_minWidth && m_cachedConstraintMinWidth == constraints.minWidth &&
      m_cachedConstraintMaxWidth == constraints.maxWidth && m_cachedHasConstraintMaxWidth == constraints.hasMaxWidth &&
      m_cachedTextAlign == align && m_cachedStableBaseline == m_stableBaseline) {
    return LayoutSize{.width = width(), .height = height()};
  }
  auto metrics = renderer.measureText(m_textNode->text(), m_textNode->fontSize(), m_textNode->bold(), measureMaxWidth,
                                      maxLines, align);
  auto refMetrics = renderer.measureText("A", m_textNode->fontSize(), m_textNode->bold());
  const float measuredWidth = measureMaxWidth > 0.0f ? std::min(metrics.width, measureMaxWidth) : metrics.width;
  const bool hasAssignedWidth = constraints.hasExactWidth();
  const float assignedWidth = constraints.maxWidth;

  const float refHeight = refMetrics.bottom - refMetrics.top;
  const float actualHeight = metrics.bottom - metrics.top;
  const float inkHeight = std::max(0.0f, metrics.inkBottom - metrics.inkTop);
  // Keep single-line labels on the same reference height as glyphs, but center
  // the visible text ink within that height so digits and symbols do not read
  // optically low beside icons.
  if (singleLine && inkHeight > 0.0f) {
    // Stable-baseline labels center on the caps reference ("A") instead of the
    // current text's ink. That keeps caps at a fixed y across text changes
    // (e.g. a clock cycling "Mar" → "Apr") AND matches the y-position used by
    // sibling dynamic-mode labels whose text happens to be caps-only (e.g. a
    // weather capsule reading "15°C"), so they align horizontally.
    float inkTopForCentering = metrics.inkTop;
    float inkHeightForCentering = inkHeight;
    if (m_stableBaseline) {
      const float capInkHeight = std::max(0.0f, refMetrics.inkBottom - refMetrics.inkTop);
      if (capInkHeight > 0.0f) {
        inkTopForCentering = refMetrics.inkTop;
        inkHeightForCentering = capInkHeight;
      }
    }
    // Round height BEFORE computing the ink-centering offset so the ink center
    // lands at the geometric center of the rounded (visible) box, not the
    // unrounded refHeight — otherwise callers that center the label box inside
    // a parent see the ink offset by up to 0.5px.
    const float height = std::round(std::max(refHeight, inkHeight));
    m_baselineOffset = -inkTopForCentering + (height - inkHeightForCentering) * 0.5f;
    const float finalWidth =
        hasAssignedWidth ? std::max(assignedWidth, m_minWidth) : std::max(measuredWidth, m_minWidth);
    setSize(std::round(finalWidth), height);
  } else {
    m_baselineOffset = -std::min(refMetrics.top, metrics.top);
    const float inkBottom = m_baselineOffset + metrics.bottom;
    const float height = std::max({refHeight, actualHeight, inkBottom});
    const float finalWidth =
        hasAssignedWidth ? std::max(assignedWidth, m_minWidth) : std::max(measuredWidth, m_minWidth);
    setSize(std::round(finalWidth), std::round(height));
  }
  if (width() < m_minWidth) {
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
  m_cachedMaxWidth = configuredMaxWidth;
  m_cachedMaxLines = maxLines;
  m_cachedMinWidth = m_minWidth;
  m_cachedConstraintMinWidth = constraints.minWidth;
  m_cachedConstraintMaxWidth = constraints.maxWidth;
  m_cachedHasConstraintMaxWidth = constraints.hasMaxWidth;
  m_cachedTextAlign = align;
  m_cachedStableBaseline = m_stableBaseline;
  m_measureCached = true;
  return LayoutSize{.width = width(), .height = height()};
}
