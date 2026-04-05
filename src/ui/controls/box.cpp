#include "ui/controls/box.h"

#include "render/programs/rounded_rect_program.h"
#include "render/scene/rect_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

Box::Box() {
  auto rect = std::make_unique<RectNode>();
  m_rect = static_cast<RectNode*>(addChild(std::move(rect)));
}

void Box::setFill(const Color& color) {
  auto style = m_rect->style();
  style.fill = color;
  style.fillMode = FillMode::Solid;
  m_rect->setStyle(style);
}

void Box::setBorder(const Color& color, float width) {
  auto style = m_rect->style();
  style.border = color;
  style.borderWidth = width;
  m_rect->setStyle(style);
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

void Box::setCardStyle() {
  auto style = m_rect->style();
  style.fill = palette.surface;
  style.border = palette.outline;
  style.fillMode = FillMode::Solid;
  style.radius = Style::radiusMd;
  style.softness = 1.0f;
  style.borderWidth = Style::borderWidth;
  m_rect->setStyle(style);
}

void Box::setPanelStyle() {
  auto style = m_rect->style();
  style.fill = palette.surface;
  style.border = palette.outline;
  style.fillMode = FillMode::Solid;
  style.radius = Style::radiusLg;
  style.softness = 1.2f;
  style.borderWidth = Style::borderWidth;
  m_rect->setStyle(style);
}

void Box::setSize(float w, float h) {
  Node::setSize(w, h);
  m_rect->setSize(w, h);
}
