#include "ui/controls/glyph.h"

#include "render/core/renderer.h"
#include "render/scene/glyph_node.h"
#include "ui/controls/glyph_registry.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>

Glyph::Glyph() {
  auto glyph = std::make_unique<GlyphNode>();
  m_glyphNode = static_cast<GlyphNode*>(addChild(std::move(glyph)));
  m_logicalFontSize = Style::fontSizeBody;
  m_glyphNode->setFontSize(m_logicalFontSize);
  applyPalette();
  m_paletteConn = paletteChanged().connect([this] { applyPalette(); });
}

void Glyph::setGlyph(std::string_view name) {
  char32_t cp = GlyphRegistry::lookup(name);
  if (cp != 0 && cp != m_glyphNode->codepoint()) {
    m_glyphNode->setCodepoint(cp);
    m_measureCached = false;
  }
}

void Glyph::setCodepoint(char32_t codepoint) {
  if (codepoint != m_glyphNode->codepoint()) {
    m_glyphNode->setCodepoint(codepoint);
    m_measureCached = false;
  }
}

void Glyph::setGlyphSize(float size) {
  if (size == m_logicalFontSize) {
    return;
  }
  m_logicalFontSize = size;
  m_glyphNode->setFontSize(size);
  m_measureCached = false;
}

void Glyph::setColor(const ThemeColor& color) {
  m_color = color;
  applyPalette();
}

void Glyph::setColor(const Color& color) { setColor(fixedColor(color)); }

void Glyph::applyPalette() { m_glyphNode->setColor(resolveThemeColor(m_color)); }

void Glyph::doLayout(Renderer& renderer) { measure(renderer); }

void Glyph::measure(Renderer& renderer) {
  const float assignedWidth = width();
  const float curFlexGrow = flexGrow();
  if (m_measureCached && m_cachedCodepoint == m_glyphNode->codepoint() && m_cachedFontSize == m_glyphNode->fontSize() &&
      m_cachedLogicalFontSize == m_logicalFontSize && m_cachedAssignedWidth == assignedWidth &&
      m_cachedFlexGrow == curFlexGrow) {
    return;
  }
  auto metrics = renderer.measureGlyph(m_glyphNode->codepoint(), m_glyphNode->fontSize());
  auto refMetrics = renderer.measureText("A", m_logicalFontSize);

  // Bounding box uses the "A" text reference — same height as Label — so glyphs
  // and labels at the same font size are treated identically by Flex layout.
  m_baselineOffset = -refMetrics.top;
  const bool preserveAssignedWidth = flexGrow() > 0.0f && assignedWidth > 0.0f;
  const float finalWidth = preserveAssignedWidth ? assignedWidth : metrics.width;
  Node::setSize(std::round(finalWidth), std::round(refMetrics.bottom - refMetrics.top));

  // MDI glyphs fill more of the em-square than text, so placing the glyph at
  // the text baseline leaves its ink above the label's ink. Center the glyph
  // ink on the reference ink center (computed from rounded container height so
  // glyph and label containers agree on the same midline at any scale).
  const float containerHeight = height();
  const float glyphCenterX = (metrics.left + metrics.right) * 0.5f;
  const float glyphInkCenter = (metrics.top + metrics.bottom) * 0.5f; // relative to baseline
  const float glyphNodeY = containerHeight * 0.5f - glyphInkCenter;
  m_glyphNode->setPosition(std::round(width() * 0.5f - glyphCenterX), std::round(glyphNodeY));

  m_cachedCodepoint = m_glyphNode->codepoint();
  m_cachedFontSize = m_glyphNode->fontSize();
  m_cachedLogicalFontSize = m_logicalFontSize;
  m_cachedAssignedWidth = assignedWidth;
  m_cachedFlexGrow = curFlexGrow;
  m_measureCached = true;
}
