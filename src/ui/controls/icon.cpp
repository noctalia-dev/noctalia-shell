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
  auto metrics = renderer.measureGlyph(m_iconNode->codepoint(), m_iconNode->fontSize());
  Node::setSize(std::round(metrics.width), std::round(metrics.bottom - metrics.top));
  m_baselineOffset = -metrics.top;
  m_iconNode->setPosition(0.0f, m_baselineOffset);
}
