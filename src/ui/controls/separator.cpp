#include "ui/controls/separator.h"

#include "render/core/render_styles.h"
#include "render/scene/rect_node.h"
#include "ui/controls/flex.h"

#include <memory>

Separator::Separator() {
  m_rectStart = static_cast<RectNode*>(addChild(std::make_unique<RectNode>()));
  m_rectEnd = static_cast<RectNode*>(addChild(std::make_unique<RectNode>()));
  m_paletteConn = paletteChanged().connect([this] { applyPalette(); });
  applyPalette();
}

void Separator::setColor(const ColorSpec& color) {
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
    const float halfW = w * 0.5f;
    m_rectStart->setPosition(0.0f, 0.0f);
    m_rectStart->setFrameSize(halfW, m_thickness);
    m_rectEnd->setPosition(halfW, 0.0f);
    m_rectEnd->setFrameSize(w - halfW, m_thickness);
  } else {
    const float h = height() > 0.0f ? height() : (parent() != nullptr ? parent()->height() : 0.0f);
    setSize(m_thickness, h);
    const float halfH = h * 0.5f;
    m_rectStart->setPosition(0.0f, 0.0f);
    m_rectStart->setFrameSize(m_thickness, halfH);
    m_rectEnd->setPosition(0.0f, halfH);
    m_rectEnd->setFrameSize(m_thickness, h - halfH);
  }

  applyPalette();
}

void Separator::applyPalette() {
  bool horizontal = true;
  if (auto* flex = dynamic_cast<Flex*>(parent()); flex != nullptr) {
    horizontal = flex->direction() == FlexDirection::Vertical;
  }

  const Color opaque = resolveColorSpec(m_color);
  Color transparent = opaque;
  transparent.a = 0.0f;
  const GradientDirection dir = horizontal ? GradientDirection::Horizontal : GradientDirection::Vertical;

  m_rectStart->setStyle(RoundedRectStyle{
      .fill = transparent,
      .border = clearColor(),
      .fillMode = FillMode::LinearGradient,
      .gradientDirection = dir,
      .gradientStops = {GradientStop{0.0f, transparent}, GradientStop{0.0f, transparent}, GradientStop{1.0f, opaque},
                        GradientStop{1.0f, opaque}},
      .radius = 0.0f,
      .softness = 0.0f,
      .borderWidth = 0.0f,
  });

  m_rectEnd->setStyle(RoundedRectStyle{
      .fill = opaque,
      .border = clearColor(),
      .fillMode = FillMode::LinearGradient,
      .gradientDirection = dir,
      .gradientStops = {GradientStop{0.0f, opaque}, GradientStop{0.0f, opaque}, GradientStop{1.0f, transparent},
                        GradientStop{1.0f, transparent}},
      .radius = 0.0f,
      .softness = 0.0f,
      .borderWidth = 0.0f,
  });
}
