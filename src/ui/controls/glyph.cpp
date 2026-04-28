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

bool Glyph::setGlyph(std::string_view name) {
  char32_t cp = GlyphRegistry::lookup(name);
  if (cp == 0 || cp == m_glyphNode->codepoint())
    return false;
  m_glyphNode->setCodepoint(cp);
  m_measureCached = false;
  return true;
}

bool Glyph::setCodepoint(char32_t codepoint) {
  if (codepoint == m_glyphNode->codepoint())
    return false;
  m_glyphNode->setCodepoint(codepoint);
  m_measureCached = false;
  return true;
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

void Glyph::setShadow(const Color& color, float offsetX, float offsetY) {
  m_glyphNode->setShadow(color, offsetX, offsetY);
}

void Glyph::clearShadow() { m_glyphNode->clearShadow(); }

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

  // Tabler icons are designed on a square viewport. Keep layout stable by
  // exposing that square instead of each icon's ink box; only the internal
  // glyph origin uses measured ink extents for centering.
  const bool preserveAssignedWidth = flexGrow() > 0.0f && assignedWidth > 0.0f;
  const float boxSize = std::round(m_logicalFontSize);
  const float finalWidth = preserveAssignedWidth ? assignedWidth : boxSize;
  Node::setSize(std::round(finalWidth), boxSize);

  const float glyphCenterX = (metrics.left + metrics.right) * 0.5f;
  const float glyphInkCenter = (metrics.top + metrics.bottom) * 0.5f; // relative to baseline
  m_baselineOffset = height() * 0.5f - glyphInkCenter;
  m_glyphNode->setPosition(width() * 0.5f - glyphCenterX, m_baselineOffset);

  m_cachedCodepoint = m_glyphNode->codepoint();
  m_cachedFontSize = m_glyphNode->fontSize();
  m_cachedLogicalFontSize = m_logicalFontSize;
  m_cachedAssignedWidth = assignedWidth;
  m_cachedFlexGrow = curFlexGrow;
  m_measureCached = true;
}
