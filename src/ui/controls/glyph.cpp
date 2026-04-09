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
  m_glyphNode->setFontSize(Style::fontSizeBody);
  m_glyphNode->setColor(palette.onSurface);
}

void Glyph::setGlyph(std::string_view name) {
  char32_t cp = GlyphRegistry::lookup(name);
  if (cp != 0) {
    m_glyphNode->setCodepoint(cp);
  }
}

void Glyph::setCodepoint(char32_t codepoint) { m_glyphNode->setCodepoint(codepoint); }

void Glyph::setGlyphSize(float size) { m_glyphNode->setFontSize(size); }

void Glyph::setColor(const Color& color) { m_glyphNode->setColor(color); }

void Glyph::layout(Renderer& renderer) { measure(renderer); }

void Glyph::measure(Renderer& renderer) {
  auto metrics    = renderer.measureGlyph(m_glyphNode->codepoint(), m_glyphNode->fontSize());
  auto refMetrics = renderer.measureText("A", m_glyphNode->fontSize());

  // Bounding box uses the "A" text reference — same height as Label — so glyphs
  // and labels at the same font size are treated identically by Flex layout.
  m_baselineOffset = -refMetrics.top;
  Node::setSize(std::round(metrics.width), std::round(refMetrics.bottom - refMetrics.top));

  // Glyph glyphs (MDI) fill more of the em-square than text glyphs, so placing
  // the glyph at the text baseline leaves its ink center above the label ink center.
  // Instead, compute the Y that puts the glyph ink center at the reference center,
  // matching where label ink sits regardless of per-glyph metrics.
  const float refCenter = (refMetrics.bottom - refMetrics.top) * 0.5f;
  const float glyphInkCenter = (metrics.top + metrics.bottom) * 0.5f; // relative to baseline
  const float glyphCenterX = (metrics.left + metrics.right) * 0.5f;
  m_glyphNode->setPosition(std::round(width() * 0.5f - glyphCenterX), refCenter - glyphInkCenter);
}
