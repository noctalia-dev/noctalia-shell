#include "ui/controls/icon.h"

#include "render/core/renderer.h"
#include "render/scene/icon_node.h"
#include "ui/icons/icon_registry.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>

Icon::Icon() {
  auto iconNode = std::make_unique<IconNode>();
  m_iconNode = static_cast<IconNode*>(addChild(std::move(iconNode)));
  m_iconNode->setFontSize(Style::fontSizeBody);
  m_iconNode->setColor(palette.onSurface);
}

void Icon::setIcon(std::string_view name) {
  char32_t cp = IconRegistry::lookup(name);
  if (cp != 0) {
    m_iconNode->setCodepoint(cp);
  }
}

void Icon::setCodepoint(char32_t codepoint) { m_iconNode->setCodepoint(codepoint); }

void Icon::setIconSize(float size) { m_iconNode->setFontSize(size); }

void Icon::setColor(const Color& color) { m_iconNode->setColor(color); }

void Icon::measure(Renderer& renderer) {
  auto metrics    = renderer.measureGlyph(m_iconNode->codepoint(), m_iconNode->fontSize());
  auto refMetrics = renderer.measureText("A", m_iconNode->fontSize());

  // Bounding box uses the "A" text reference — same height as Label — so icons
  // and labels at the same font size are treated identically by Flex layout.
  m_baselineOffset = -refMetrics.top;
  Node::setSize(std::round(metrics.width), std::round(refMetrics.bottom - refMetrics.top));

  // Icon glyphs (MDI) fill more of the em-square than text glyphs, so placing
  // the icon at the text baseline leaves its ink center above the label ink center.
  // Instead, compute the Y that puts the icon ink center at the reference center,
  // matching where label ink sits regardless of per-glyph metrics.
  const float refCenter     = (refMetrics.bottom - refMetrics.top) * 0.5f;
  const float iconInkCenter = (metrics.top + metrics.bottom) * 0.5f; // relative to baseline
  m_iconNode->setPosition(0.0f, refCenter - iconInkCenter);
}
