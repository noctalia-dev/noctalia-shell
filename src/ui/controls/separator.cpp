#include "ui/controls/separator.h"

#include "render/programs/rect_program.h"
#include "render/scene/rect_node.h"
#include "ui/controls/flex.h"

#include <memory>

Separator::Separator() {
  auto rect = std::make_unique<RectNode>();
  m_rect = static_cast<RectNode*>(addChild(std::move(rect)));
  m_paletteConn = paletteChanged().connect([this] { applyPalette(); });
  applyPalette();
}

void Separator::setColor(const ThemeColor& color) {
  m_color = color;
  applyPalette();
}

void Separator::setThickness(float thickness) {
  m_thickness = thickness;
  markLayoutDirty();
}

void Separator::doLayout(Renderer& /*renderer*/) {
  bool horizontal = true;
  if (auto* flex = dynamic_cast<Flex*>(parent()); flex != nullptr) {
    horizontal = flex->direction() == FlexDirection::Vertical;
  }

  if (horizontal) {
    const float w = width() > 0.0f ? width() : (parent() != nullptr ? parent()->width() : 0.0f);
    setSize(w, m_thickness);
    m_rect->setFrameSize(w, m_thickness);
  } else {
    const float h = height() > 0.0f ? height() : (parent() != nullptr ? parent()->height() : 0.0f);
    setSize(m_thickness, h);
    m_rect->setFrameSize(m_thickness, h);
  }
}

void Separator::applyPalette() {
  m_rect->setStyle(RoundedRectStyle{
      .fill = resolveThemeColor(m_color),
      .border = clearColor(),
      .fillMode = FillMode::Solid,
      .radius = 0.0f,
      .softness = 0.0f,
      .borderWidth = 0.0f,
  });
}
