#include "ui/controls/box.h"

#include "render/programs/rounded_rect_program.h"
#include "render/scene/rect_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

Box::Box() {
  auto rect = std::make_unique<RectNode>();
  m_rect = static_cast<RectNode*>(addChild(std::move(rect)));
  m_paletteConn = paletteChanged().connect([this] { applyPalette(); });
}

void Box::setFill(const ThemeColor& color) {
  m_fill = color;
  applyPalette();
}

void Box::setFill(const Color& color) { setFill(fixedColor(color)); }

void Box::setBorder(const ThemeColor& color, float width) {
  m_border = color;
  m_borderWidth = width;
  applyPalette();
}

void Box::setBorder(const Color& color, float width) { setBorder(fixedColor(color), width); }

void Box::clearBorder() {
  m_border = clearThemeColor();
  m_borderWidth = 0.0f;
  applyPalette();
}

void Box::setRadius(float radius) {
  auto style = m_rect->style();
  style.radius = radius;
  m_rect->setStyle(style);
}

void Box::setSoftness(float softness) {
  auto style = m_rect->style();
  style.softness = softness;
  m_rect->setStyle(style);
}

void Box::setSize(float w, float h) {
  Node::setSize(w, h);
  m_rect->setFrameSize(w, h);
}

void Box::setFrameSize(float w, float h) {
  Node::setFrameSize(w, h);
  m_rect->setFrameSize(w, h);
}

void Box::setFlatStyle() {
  m_fill = roleColor(ColorRole::Surface);
  m_border = roleColor(ColorRole::Outline);
  m_borderWidth = 0.0f;
  auto style = m_rect->style();
  style.fill = resolveThemeColor(m_fill);
  style.border = resolveThemeColor(m_border);
  style.borderWidth = m_borderWidth;
  style.fillMode = FillMode::Solid;
  style.radius = 0;
  style.softness = 0;
  m_rect->setStyle(style);
}

void Box::setCardStyle() {
  m_fill = roleColor(ColorRole::Surface);
  m_border = roleColor(ColorRole::Outline);
  m_borderWidth = Style::borderWidth;
  auto style = m_rect->style();
  style.fill = resolveThemeColor(m_fill);
  style.border = resolveThemeColor(m_border);
  style.borderWidth = m_borderWidth;
  style.fillMode = FillMode::Solid;
  style.radius = Style::radiusMd;
  style.softness = 1.2f;
  m_rect->setStyle(style);
}

void Box::setPanelStyle() {
  m_fill = roleColor(ColorRole::Surface);
  m_border = roleColor(ColorRole::Outline);
  m_borderWidth = Style::borderWidth;
  auto style = m_rect->style();
  style.fill = resolveThemeColor(m_fill);
  style.border = resolveThemeColor(m_border);
  style.borderWidth = m_borderWidth;
  style.fillMode = FillMode::Solid;
  style.radius = Style::radiusXl;
  style.softness = 1.2f;
  m_rect->setStyle(style);
}

void Box::applyPalette() {
  auto style = m_rect->style();
  style.fill = resolveThemeColor(m_fill);
  style.border = resolveThemeColor(m_border);
  style.borderWidth = m_borderWidth;
  style.fillMode = FillMode::Solid;
  m_rect->setStyle(style);
}
