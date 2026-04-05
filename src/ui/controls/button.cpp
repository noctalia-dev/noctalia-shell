#include "ui/controls/button.h"

#include "render/animation/animation_manager.h"
#include "render/scene/input_area.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <cmath>
#include <memory>

Button::Button() {
  setAlign(FlexAlign::Center);
  setMinHeight(Style::controlHeight);
  setPadding(Style::paddingV, Style::paddingH, Style::paddingV, Style::paddingH);
  setRadius(Style::radiusMd);

  auto label = std::make_unique<Label>();
  m_label = static_cast<Label*>(addChild(std::move(label)));
  applyVariant();
}

void Button::setText(std::string_view text) { m_label->setText(text); }

void Button::setIcon(std::string_view name) {
  ensureIcon();
  m_icon->setIcon(name);
}

void Button::setFontSize(float size) {
  m_label->setFontSize(size);
  if (m_icon != nullptr) {
    m_icon->setIconSize(size);
  }
}

void Button::setIconSize(float size) {
  ensureIcon();
  m_icon->setIconSize(size);
}

void Button::setOnClick(std::function<void()> callback) {
  m_onClick = std::move(callback);

  // Lazily create InputArea on first setOnClick
  if (m_inputArea == nullptr) {
    auto area = std::make_unique<InputArea>();
    area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyVisualState(); });
    area->setOnLeave([this]() { applyVisualState(); });
    area->setOnPress([this](const InputArea::PointerData& /*data*/) { applyVisualState(); });
    area->setOnClick([this](const InputArea::PointerData& /*data*/) {
      if (m_onClick) {
        m_onClick();
      }
      applyVisualState();
    });
    m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }
}

void Button::setCursorShape(std::uint32_t shape) {
  if (m_inputArea != nullptr) {
    m_inputArea->setCursorShape(shape);
  }
}

void Button::updateInputArea() {
  if (m_inputArea != nullptr) {
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }
}

bool Button::hovered() const noexcept { return m_inputArea != nullptr && m_inputArea->hovered(); }

bool Button::pressed() const noexcept { return m_inputArea != nullptr && m_inputArea->pressed(); }

void Button::setVariant(ButtonVariant variant) {
  if (m_variant == variant) {
    return;
  }
  m_variant = variant;
  applyVariant();
}

void Button::applyVariant() {
  setPadding(Style::paddingV, Style::paddingH, Style::paddingV, Style::paddingH);
  setRadius(Style::radiusMd);
  setBorderWidth(Style::borderWidth);

  switch (m_variant) {
  case ButtonVariant::Default:
    // Resting state is neutral; pressed state uses active (workspace-like) color.
    m_bgColorNormal = palette.surfaceVariant;
    m_bgColorHover = brighten(m_bgColorNormal, 1.14f);
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSurface;
    m_labelColorHover = palette.onSurface;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = brighten(m_borderColorNormal, 1.14f);
    m_borderColorPressed = palette.primary;
    break;
  case ButtonVariant::Secondary:
    m_bgColorNormal = palette.secondary;
    m_bgColorHover = brighten(m_bgColorNormal, 1.12f);
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSecondary;
    m_labelColorHover = palette.onSecondary;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = brighten(m_borderColorNormal, 1.14f);
    m_borderColorPressed = palette.primary;
    break;
  case ButtonVariant::Destructive:
    m_bgColorNormal = palette.error;
    m_bgColorHover = brighten(m_bgColorNormal, 1.1f);
    m_bgColorPressed = palette.error;
    m_labelColorNormal = palette.onError;
    m_labelColorHover = palette.onError;
    m_labelColorPressed = palette.onError;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = brighten(m_borderColorNormal, 1.14f);
    m_borderColorPressed = palette.error;
    break;
  case ButtonVariant::Outline:
    m_bgColorNormal = palette.surface;
    m_bgColorHover = brighten(m_bgColorNormal, 1.12f);
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSurface;
    m_labelColorHover = palette.onSurface;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = brighten(m_borderColorNormal, 1.14f);
    m_borderColorPressed = palette.primary;
    break;
  case ButtonVariant::Ghost:
    m_bgColorNormal = palette.surface;
    m_bgColorHover = brighten(m_bgColorNormal, 1.12f);
    m_bgColorPressed = palette.primary;
    m_labelColorNormal = palette.onSurface;
    m_labelColorHover = palette.onSurface;
    m_labelColorPressed = palette.onPrimary;
    m_borderColorNormal = palette.outline;
    m_borderColorHover = brighten(m_borderColorNormal, 1.14f);
    m_borderColorPressed = palette.primary;
    break;
  }

  // Seed animation state so the first transition has valid starting colors.
  m_targetBg = m_bgColorNormal;
  m_targetBorder = m_borderColorNormal;
  m_targetLabel = m_labelColorNormal;
  applyVisualState();
}

void Button::ensureIcon() {
  if (m_icon != nullptr) {
    return;
  }
  // Insert icon before the label so it appears on the left
  auto& kids = children();
  std::size_t labelIndex = 0;
  for (std::size_t i = 0; i < kids.size(); ++i) {
    if (kids[i].get() == m_label) {
      labelIndex = i;
      break;
    }
  }
  auto icon = std::make_unique<Icon>();
  m_icon = static_cast<Icon*>(insertChildAt(labelIndex, std::move(icon)));
  setDirection(FlexDirection::Horizontal);
  setGap(Style::spaceXs);
}

void Button::applyColors(const Color& bg, const Color& border, const Color& label) {
  setBackground(bg);
  setBorderColor(border);
  m_label->setColor(label);
  if (m_icon != nullptr) {
    m_icon->setColor(label);
  }
}

void Button::applyVisualState() {
  bool isHovered = hovered();
  bool isPressed = pressed();

  Color targetBg;
  Color targetBorder;
  Color targetLabel;
  if (isPressed) {
    targetBg = m_bgColorPressed;
    targetBorder = m_borderColorPressed;
    targetLabel = m_labelColorPressed;
  } else if (isHovered) {
    targetBg = m_bgColorHover;
    targetBorder = m_borderColorHover;
    targetLabel = m_labelColorHover;
  } else {
    targetBg = m_bgColorNormal;
    targetBorder = m_borderColorNormal;
    targetLabel = m_labelColorNormal;
  }

  if (animationManager() == nullptr) {
    applyColors(targetBg, targetBorder, targetLabel);
    return;
  }

  // Snapshot current display colors as the animation start point
  m_fromBg = m_targetBg;
  m_fromBorder = m_targetBorder;
  m_fromLabel = m_targetLabel;
  m_targetBg = targetBg;
  m_targetBorder = targetBorder;
  m_targetLabel = targetLabel;

  if (m_animId != 0) {
    animationManager()->cancel(m_animId);
  }

  m_animId = animationManager()->animate(
      0.0f, 1.0f, Style::animFast, Easing::EaseOutCubic,
      [this](float t) {
        applyColors(lerpColor(m_fromBg, m_targetBg, t), lerpColor(m_fromBorder, m_targetBorder, t),
                    lerpColor(m_fromLabel, m_targetLabel, t));
      },
      [this]() { m_animId = 0; });
  markDirty();
}

void Button::layout(Renderer& renderer) {
  if (m_label == nullptr) {
    return;
  }

  m_label->measure(renderer);
  if (m_icon != nullptr) {
    m_icon->measure(renderer);
  }

  if (m_inputArea != nullptr) {
    m_inputArea->setVisible(false);
  }

  Flex::layout(renderer);

  // Geometric centering of the full label bbox (including descender space)
  // makes cap letters appear too high. Pure cap-height centering over-corrects.
  // Nudge down by 1/4 of the descender depth as a compromise.
  float descender = m_label->height() - m_label->baselineOffset();
  float labelY = std::round((height() - m_label->height()) * 0.5f + descender * 0.25f);

  if (m_icon == nullptr) {
    m_label->setPosition(std::round((width() - m_label->width()) * 0.5f), labelY);
  } else {
    // Keep Flex's x positions; only adjust y for optical centering.
    // Center the icon to the cap-height center (midpoint of ascender range),
    // not the full label bbox which includes descender space.
    m_label->setPosition(m_label->x(), labelY);
    float capCenterY = labelY + m_label->baselineOffset() * 0.5f;
    m_icon->setPosition(m_icon->x(), std::round(capCenterY - m_icon->height() * 0.5f));
  }

  if (m_inputArea != nullptr) {
    m_inputArea->setVisible(true);
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }

  // Only apply visual state if no animation is in progress — a running
  // animation already owns the color transition and re-calling here would
  // reset its from/to snapshot, collapsing the animation to a no-op.
  if (m_animId == 0) {
    applyVisualState();
  }
}
