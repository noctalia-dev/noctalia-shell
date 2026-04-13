#include "ui/controls/flex.h"

#include "render/core/renderer.h"
#include "render/programs/rect_program.h"
#include "render/scene/rect_node.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

Flex::Flex() { m_paletteConn = paletteChanged().connect([this] { applyPalette(); }); }

void Flex::setSize(float width, float height) {
  Node::setSize(width, height);
  if (m_background != nullptr) {
    m_background->setPosition(0.0f, 0.0f);
    m_background->setFrameSize(width, height);
  }
}

void Flex::setFrameSize(float width, float height) {
  Node::setFrameSize(width, height);
  if (m_background != nullptr) {
    m_background->setPosition(0.0f, 0.0f);
    m_background->setFrameSize(width, height);
  }
}

void Flex::setDirection(FlexDirection direction) {
  if (m_direction == direction) {
    return;
  }
  m_direction = direction;
  markLayoutDirty();
}

void Flex::setGap(float gap) {
  if (m_gap == gap) {
    return;
  }
  m_gap = gap;
  markLayoutDirty();
}

void Flex::setAlign(FlexAlign align) {
  if (m_align == align) {
    return;
  }
  m_align = align;
  markLayoutDirty();
}

void Flex::setJustify(FlexJustify justify) {
  if (m_justify == justify) {
    return;
  }
  m_justify = justify;
  markLayoutDirty();
}

void Flex::setPadding(float top, float right, float bottom, float left) {
  m_paddingTop = top;
  m_paddingRight = right;
  m_paddingBottom = bottom;
  m_paddingLeft = left;
  markLayoutDirty();
}

void Flex::setPadding(float all) { setPadding(all, all, all, all); }

void Flex::setPadding(float vertical, float horizontal) { setPadding(vertical, horizontal, vertical, horizontal); }

void Flex::setBackground(const ThemeColor& color) {
  m_backgroundColor = color;
  ensureBackground();
  applyPalette();
}

void Flex::setBackground(const Color& color) { setBackground(fixedColor(color)); }

void Flex::clearBackground() {
  m_backgroundColor = clearThemeColor();
  if (m_background != nullptr) {
    applyPalette();
  }
}

void Flex::setRadius(float radius) {
  ensureBackground();
  auto style = m_background->style();
  style.radius = radius;
  m_background->setStyle(style);
}

void Flex::setBorderColor(const ThemeColor& color) {
  m_borderColor = color;
  ensureBackground();
  applyPalette();
}

void Flex::setBorderColor(const Color& color) { setBorderColor(fixedColor(color)); }

void Flex::clearBorder() {
  m_borderColor = clearThemeColor();
  if (m_background != nullptr) {
    auto style = m_background->style();
    style.borderWidth = 0.0f;
    m_background->setStyle(style);
    applyPalette();
  }
}

void Flex::applyPalette() {
  if (m_background == nullptr) {
    return;
  }
  auto style = m_background->style();
  style.fill = resolveThemeColor(m_backgroundColor);
  style.border = resolveThemeColor(m_borderColor);
  style.fillMode = FillMode::Solid;
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
  markLayoutDirty();
}

void Flex::setMinHeight(float minHeight) {
  if (m_minHeight == minHeight) {
    return;
  }
  m_minHeight = minHeight;
  markLayoutDirty();
}

void Flex::setFillParentMainAxis(bool fill) {
  if (m_fillParentMainAxis == fill) {
    return;
  }
  m_fillParentMainAxis = fill;
  markLayoutDirty();
}

void Flex::setRowLayout() {
  setDirection(FlexDirection::Horizontal);
  setGap(Style::spaceXs);
  setAlign(FlexAlign::Center);
  setJustify(FlexJustify::Start);
}

void Flex::ensureBackground() {
  if (m_background != nullptr) {
    return;
  }
  auto rect = std::make_unique<RectNode>();
  rect->setStyle(RoundedRectStyle{
      .fill = rgba(0, 0, 0, 0),
      .border = rgba(0, 0, 0, 0),
      .fillMode = FillMode::Solid,
      .radius = 0.0f,
      .softness = 0.0f,
      .borderWidth = 0.0f,
  });
  m_background = static_cast<RectNode*>(addChild(std::move(rect)));
  m_background->setZIndex(-1);
  m_background->setFrameSize(width(), height());
  applyPalette();
}

void Flex::doLayout(Renderer& renderer) {
  auto& kids = children();
  const bool horizontal = m_direction == FlexDirection::Horizontal;
  const float containerMain = horizontal ? width() : height();
  const float containerCross = horizontal ? height() : width();

  // Pass 0: Stretch — pre-set cross-axis size on children before measurement.
  if (m_align == FlexAlign::Stretch && containerCross > 0.0f) {
    const float availCross = horizontal ? (containerCross - m_paddingTop - m_paddingBottom)
                                        : (containerCross - m_paddingLeft - m_paddingRight);
    for (auto& child : kids) {
      if (!child->visible() || !child->participatesInLayout() || child.get() == m_background) {
        continue;
      }
      if (horizontal) {
        child->setSize(child->width(), availCross);
      } else {
        child->setSize(availCross, child->height());
      }
    }
  }

  // Pass 1: Measure non-grow children (skip grow children — they need sizing first).
  float totalGrow = 0.0f;
  for (auto& child : kids) {
    if (!child->visible() || !child->participatesInLayout() || child.get() == m_background) {
      continue;
    }
    if (child->flexGrow() > 0.0f) {
      totalGrow += child->flexGrow();
      continue;
    }
    child->layout(renderer);
  }

  // Pass 2: Distribute remaining main-axis space to grow children.
  if (totalGrow > 0.0f && containerMain > 0.0f) {
    float fixedTotal = horizontal ? (m_paddingLeft + m_paddingRight) : (m_paddingTop + m_paddingBottom);
    int visibleCount = 0;
    for (auto& child : kids) {
      if (!child->visible() || !child->participatesInLayout() || child.get() == m_background) {
        continue;
      }
      ++visibleCount;
      if (child->flexGrow() > 0.0f) {
        continue;
      }
      fixedTotal += horizontal ? child->width() : child->height();
    }
    if (visibleCount > 1) {
      fixedTotal += m_gap * static_cast<float>(visibleCount - 1);
    }

    const float remaining = std::max(0.0f, containerMain - fixedTotal);
    for (auto& child : kids) {
      if (!child->visible() || !child->participatesInLayout() || child.get() == m_background ||
          child->flexGrow() <= 0.0f) {
        continue;
      }
      const float share = remaining * (child->flexGrow() / totalGrow);
      if (horizontal) {
        child->setSize(share, child->height());
      } else {
        child->setSize(child->width(), share);
      }
      child->layout(renderer);
    }
  }

  // Pass 3: Position children along main axis.
  const float innerMain = horizontal ? std::max(0.0f, width() - m_paddingLeft - m_paddingRight)
                                     : std::max(0.0f, height() - m_paddingTop - m_paddingBottom);
  float contentMain = 0.0f;
  int visibleCount = 0;
  for (auto& child : kids) {
    if (!child->visible() || !child->participatesInLayout() || child.get() == m_background) {
      continue;
    }
    ++visibleCount;
    contentMain += horizontal ? child->width() : child->height();
  }

  float effectiveGap = m_gap;
  if (m_justify == FlexJustify::SpaceBetween && visibleCount > 1) {
    const float totalChildMain = contentMain;
    effectiveGap = std::max(m_gap, (innerMain - totalChildMain) / static_cast<float>(visibleCount - 1));
  }
  if (visibleCount > 1) {
    contentMain += effectiveGap * static_cast<float>(visibleCount - 1);
  }

  float cursor = horizontal ? m_paddingLeft : m_paddingTop;
  if (m_justify == FlexJustify::Center) {
    cursor += std::max(0.0f, (innerMain - contentMain) * 0.5f);
  } else if (m_justify == FlexJustify::End) {
    cursor += std::max(0.0f, innerMain - contentMain);
  }
  float crossMax = 0.0f;
  bool first = true;

  for (auto& child : kids) {
    if (!child->visible() || !child->participatesInLayout() || child.get() == m_background) {
      continue;
    }

    if (!first) {
      cursor += effectiveGap;
    }
    first = false;

    if (horizontal) {
      child->setPosition(cursor, child->y());
      cursor += child->width();
      crossMax = std::max(crossMax, child->height());
    } else {
      child->setPosition(child->x(), cursor);
      cursor += child->height();
      crossMax = std::max(crossMax, child->width());
    }
  }

  // Compute own size. Preserve pre-set size when grow/stretch constrain it.
  const bool preserveMain = (totalGrow > 0.0f || m_fillParentMainAxis) && containerMain > 0.0f;
  const bool preserveCross = m_align == FlexAlign::Stretch && containerCross > 0.0f;
  if (horizontal) {
    const float w = preserveMain ? std::max(containerMain, m_minWidth) : std::max(cursor + m_paddingRight, m_minWidth);
    const float h = preserveCross ? std::max(containerCross, m_minHeight)
                                  : std::max(crossMax + m_paddingTop + m_paddingBottom, m_minHeight);
    setSize(w, h);
  } else {
    const float w = preserveCross ? std::max(containerCross, m_minWidth)
                                  : std::max(crossMax + m_paddingLeft + m_paddingRight, m_minWidth);
    const float h =
        preserveMain ? std::max(containerMain, m_minHeight) : std::max(cursor + m_paddingBottom, m_minHeight);
    setSize(w, h);
  }

  // Pass 4: Cross-axis alignment.
  for (auto& child : kids) {
    if (!child->visible() || !child->participatesInLayout() || child.get() == m_background) {
      continue;
    }

    if (horizontal) {
      if (m_align == FlexAlign::Stretch) {
        child->setPosition(child->x(), m_paddingTop);
      } else {
        float space = height() - m_paddingTop - m_paddingBottom - child->height();
        float offset = m_paddingTop;
        if (m_align == FlexAlign::Center) {
          offset += space * 0.5f;
        } else if (m_align == FlexAlign::End) {
          offset += space;
        }
        child->setPosition(child->x(), offset);
      }
    } else {
      if (m_align == FlexAlign::Stretch) {
        child->setPosition(m_paddingLeft, child->y());
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
  }

  // Size background to match flex container.
  if (m_background != nullptr) {
    m_background->setPosition(0.0f, 0.0f);
    m_background->setSize(width(), height());
  }
}
