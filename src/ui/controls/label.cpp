#include "ui/controls/label.h"

#include "render/core/renderer.h"
#include "render/scene/text_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
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

void Label::setBold(bool bold) { m_textNode->setBold(bold); }

const std::string& Label::text() const noexcept { return m_textNode->text(); }

float Label::fontSize() const noexcept { return m_textNode->fontSize(); }

const Color& Label::color() const noexcept { return m_textNode->color(); }

float Label::maxWidth() const noexcept { return m_textNode->maxWidth(); }

bool Label::bold() const noexcept { return m_textNode->bold(); }

void Label::setCaptionStyle() {
  m_textNode->setFontSize(Style::fontSizeCaption);
  m_textNode->setColor(palette.onSurface);
}

void Label::measure(Renderer& renderer) {
  auto metrics = renderer.measureText(m_textNode->text(), m_textNode->fontSize(), m_textNode->bold());
  setSize(std::max(metrics.width, m_minWidth), metrics.bottom - metrics.top);

  // Position the TextNode at the baseline offset within this Label's bounds
  m_textNode->setPosition(0.0f, -metrics.top);
}
