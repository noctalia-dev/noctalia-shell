#include "ui/controls/Box.hpp"

#include "render/core/Renderer.hpp"
#include "render/programs/RoundedRectProgram.hpp"
#include "render/scene/RectNode.hpp"
#include "ui/controls/Label.hpp"
#include "ui/style/Palette.hpp"
#include "ui/style/Style.hpp"

#include <algorithm>
#include <memory>

Box::Box() = default;

void Box::setDirection(BoxDirection direction) {
    if (m_direction == direction) {
        return;
    }
    m_direction = direction;
    markDirty();
}

void Box::setGap(float gap) {
    if (m_gap == gap) {
        return;
    }
    m_gap = gap;
    markDirty();
}

void Box::setAlign(BoxAlign align) {
    if (m_align == align) {
        return;
    }
    m_align = align;
    markDirty();
}

void Box::setPadding(float top, float right, float bottom, float left) {
    m_paddingTop = top;
    m_paddingRight = right;
    m_paddingBottom = bottom;
    m_paddingLeft = left;
    markDirty();
}

void Box::setPadding(float all) {
    setPadding(all, all, all, all);
}

void Box::setBackground(const Color& color) {
    ensureBackground();
    auto style = m_background->style();
    style.fill = color;
    style.fillMode = FillMode::Solid;
    m_background->setStyle(style);
}

void Box::setRadius(float radius) {
    ensureBackground();
    auto style = m_background->style();
    style.radius = radius;
    m_background->setStyle(style);
}

void Box::setBorderColor(const Color& color) {
    ensureBackground();
    auto style = m_background->style();
    style.border = color;
    m_background->setStyle(style);
}

void Box::setBorderWidth(float bw) {
    ensureBackground();
    auto style = m_background->style();
    style.borderWidth = bw;
    m_background->setStyle(style);
}

void Box::setSoftness(float softness) {
    ensureBackground();
    auto style = m_background->style();
    style.softness = softness;
    m_background->setStyle(style);
}

void Box::setCardSurface() {
    setRadius(Style::radiusMd);
    setBorderColor(kRosePinePalette.overlay);
    setBorderWidth(Style::borderWidth);
    setBackground(kRosePinePalette.surface);
}

void Box::setHorizontalRow() {
    setDirection(BoxDirection::Horizontal);
    setGap(Style::spaceXs);
    setAlign(BoxAlign::Center);
}

void Box::ensureBackground() {
    if (m_background != nullptr) {
        return;
    }
    auto rect = std::make_unique<RectNode>();
    m_background = static_cast<RectNode*>(insertChildAt(0, std::move(rect)));
}

void Box::layout(Renderer& renderer) {
    auto& kids = children();

    // First pass: measure all children (skip background)
    for (auto& child : kids) {
        if (!child->visible() || child.get() == m_background) {
            continue;
        }
        if (auto* label = dynamic_cast<Label*>(child.get())) {
            label->measure(renderer);
        }
        if (auto* box = dynamic_cast<Box*>(child.get())) {
            box->layout(renderer);
        }
    }

    // Second pass: position children along main axis
    float cursor = (m_direction == BoxDirection::Horizontal) ? m_paddingLeft : m_paddingTop;
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

        if (m_direction == BoxDirection::Horizontal) {
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
    if (m_direction == BoxDirection::Horizontal) {
        setSize(cursor + m_paddingRight, crossMax + m_paddingTop + m_paddingBottom);
    } else {
        setSize(crossMax + m_paddingLeft + m_paddingRight, cursor + m_paddingBottom);
    }

    // Third pass: cross-axis alignment
    for (auto& child : kids) {
        if (!child->visible() || child.get() == m_background) {
            continue;
        }

        if (m_direction == BoxDirection::Horizontal) {
            float space = height() - m_paddingTop - m_paddingBottom - child->height();
            float offset = m_paddingTop;
            if (m_align == BoxAlign::Center) {
                offset += space * 0.5f;
            } else if (m_align == BoxAlign::End) {
                offset += space;
            }
            child->setPosition(child->x(), offset);
        } else {
            float space = width() - m_paddingLeft - m_paddingRight - child->width();
            float offset = m_paddingLeft;
            if (m_align == BoxAlign::Center) {
                offset += space * 0.5f;
            } else if (m_align == BoxAlign::End) {
                offset += space;
            }
            child->setPosition(offset, child->y());
        }
    }

    // Size background to match box
    if (m_background != nullptr) {
        m_background->setPosition(0.0f, 0.0f);
        m_background->setSize(width(), height());
    }
}
