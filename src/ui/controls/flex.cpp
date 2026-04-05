#include "ui/controls/flex.h"

#include "render/core/renderer.h"
#include "render/programs/rounded_rect_program.h"
#include "render/scene/rect_node.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

Flex::Flex() = default;

void Flex::setDirection(FlexDirection direction) {
  if (m_direction == direction) {
    return;
  }
  m_direction = direction;
  markDirty();
}

void Flex::setGap(float gap) {
  if (m_gap == gap) {
    return;
  }
  m_gap = gap;
  markDirty();
}

void Flex::setAlign(FlexAlign align) {
  if (m_align == align) {
    return;
  }
  m_align = align;
  markDirty();
}

void Flex::setPadding(float top, float right, float bottom, float left) {
  m_paddingTop = top;
  m_paddingRight = right;
  m_paddingBottom = bottom;
  m_paddingLeft = left;
  markDirty();
}

void Flex::setPadding(float all) { setPadding(all, all, all, all); }

void Flex::setBackground(const Color& color) {
  ensureBackground();
  auto style = m_background->style();
  style.fill = color;
  style.fillMode = FillMode::Solid;
  m_background->setStyle(style);
}

void Flex::setRadius(float radius) {
  ensureBackground();
  auto style = m_background->style();
  style.radius = radius;
  m_background->setStyle(style);
}

void Flex::setBorderColor(const Color& color) {
  ensureBackground();
  auto style = m_background->style();
  style.border = color;
  m_background->setStyle(style);
}

void Flex::setBorderWidth(float bw) {
  ensureBackground();
  auto style = m_background->style();
  style.borderWidth = bw;
  m_background->setStyle(style);
}

void Flex::setSoftness(float softness) {
  ensureBackground();
  auto style = m_background->style();
  style.softness = softness;
  m_background->setStyle(style);
}

void Flex::setMinWidth(float minWidth) {
  if (m_minWidth == minWidth) {
    return;
  }
  m_minWidth = minWidth;
  markDirty();
}

void Flex::setMinHeight(float minHeight) {
  if (m_minHeight == minHeight) {
    return;
  }
  m_minHeight = minHeight;
  markDirty();
}

void Flex::setCardSurface() {
  setRadius(Style::radiusMd);
  setBorderColor(palette.outline);
  setBorderWidth(Style::borderWidth);
  setBackground(palette.surface);
}

void Flex::setRowLayout() {
  setDirection(FlexDirection::Horizontal);
  setGap(Style::spaceXs);
  setAlign(FlexAlign::Center);
}

void Flex::ensureBackground() {
  if (m_background != nullptr) {
    return;
  }
  auto rect = std::make_unique<RectNode>();
  m_background = static_cast<RectNode*>(insertChildAt(0, std::move(rect)));
}

void Flex::layout(Renderer& renderer) {
  auto& kids = children();

  // First pass: measure all children (skip background)
  for (auto& child : kids) {
    if (!child->visible() || child.get() == m_background) {
      continue;
    }
    if (auto* label = dynamic_cast<Label*>(child.get())) {
      label->measure(renderer);
    }
    if (auto* flex = dynamic_cast<Flex*>(child.get())) {
      flex->layout(renderer);
    }
  }

  // Second pass: position children along main axis
  float cursor = (m_direction == FlexDirection::Horizontal) ? m_paddingLeft : m_paddingTop;
  float crossMax = 0.0f;
  bool first = true;

  for (auto& child : kids) {
    if (!child->visible() || child.get() == m_background) {
      continue;
    }

    if (!first) {
      cursor += m_gap;
    }
    first = false;

    if (m_direction == FlexDirection::Horizontal) {
      child->setPosition(cursor, child->y());
      cursor += child->width();
      crossMax = std::max(crossMax, child->height());
    } else {
      child->setPosition(child->x(), cursor);
      cursor += child->height();
      crossMax = std::max(crossMax, child->width());
    }
  }

  // Set own size
  if (m_direction == FlexDirection::Horizontal) {
    setSize(std::max(cursor + m_paddingRight, m_minWidth), std::max(crossMax + m_paddingTop + m_paddingBottom, m_minHeight));
  } else {
    setSize(std::max(crossMax + m_paddingLeft + m_paddingRight, m_minWidth), std::max(cursor + m_paddingBottom, m_minHeight));
  }

  // Third pass: cross-axis alignment
  for (auto& child : kids) {
    if (!child->visible() || child.get() == m_background) {
      continue;
    }

    if (m_direction == FlexDirection::Horizontal) {
      float space = height() - m_paddingTop - m_paddingBottom - child->height();
      float offset = m_paddingTop;
      if (m_align == FlexAlign::Center) {
        offset += space * 0.5f;
      } else if (m_align == FlexAlign::End) {
        offset += space;
      }
      child->setPosition(child->x(), offset);
    } else {
      float space = width() - m_paddingLeft - m_paddingRight - child->width();
      float offset = m_paddingLeft;
      if (m_align == FlexAlign::Center) {
        offset += space * 0.5f;
      } else if (m_align == FlexAlign::End) {
        offset += space;
      }
      child->setPosition(offset, child->y());
    }
  }

  // Size background to match flex container
  if (m_background != nullptr) {
    m_background->setPosition(0.0f, 0.0f);
    m_background->setSize(width(), height());
  }
}
