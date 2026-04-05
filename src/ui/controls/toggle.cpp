#include "ui/controls/toggle.h"

#include "render/animation/animation_manager.h"
#include "render/core/color.h"
#include "render/programs/rounded_rect_program.h"
#include "render/scene/rect_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

Toggle::Toggle() {
  setAlign(FlexAlign::Center);
  setDirection(FlexDirection::Horizontal);
  setBorderColor(palette.outline);
  setBorderWidth(Style::borderWidth);

  auto thumb = std::make_unique<RectNode>();
  m_thumb = static_cast<RectNode*>(addChild(std::move(thumb)));

  applySize();
  applyState();
}

void Toggle::setChecked(bool checked) {
  if (m_checked == checked) {
    return;
  }
  m_checked = checked;

  if (animationManager() != nullptr) {
    if (m_animId != 0) {
      animationManager()->cancel(m_animId);
    }
    float from = m_checked ? 0.0f : 1.0f;
    float to = m_checked ? 1.0f : 0.0f;
    m_animId = animationManager()->animate(from, to, Style::animFast, Easing::EaseOutCubic,
                                     [this](float t) { applyAnimatedState(t); },
                                     [this]() { m_animId = 0; });
    // Mark dirty so the surface's frame loop restarts and ticks the animation
    markDirty();
  } else {
    applyState();
  }
}

void Toggle::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  applyState();
}

void Toggle::setToggleSize(ToggleSize size) {
  if (m_size == size) {
    return;
  }
  m_size = size;
  applySize();
  applyState();
}

void Toggle::applySize() {
  switch (m_size) {
  case ToggleSize::Small:
    m_thumbSize = 12.0f;
    m_inset = 2.0f;
    m_travel = 10.0f;
    break;
  case ToggleSize::Medium:
    m_thumbSize = 16.0f;
    m_inset = 2.0f;
    m_travel = 14.0f;
    break;
  case ToggleSize::Large:
    m_thumbSize = 18.0f;
    m_inset = 3.0f;
    m_travel = 16.0f;
    break;
  }

  m_thumb->setSize(m_thumbSize, m_thumbSize);
  setRadius((m_thumbSize + (m_inset * 2.0f)) * 0.5f);
}

void Toggle::applyState() {
  applyAnimatedState(m_checked ? 1.0f : 0.0f);
}

void Toggle::applyAnimatedState(float t) {
  const Color trackColor = lerpColor(palette.surfaceVariant, palette.primary, t);
  const Color thumbColor = lerpColor(palette.onSurfaceVariant, palette.onPrimary, t);
  const float thumbX = m_inset + m_travel * t;

  setBackground(trackColor);
  m_thumb->setPosition(thumbX, m_inset);

  auto thumbStyle = m_thumb->style();
  thumbStyle.fillMode = FillMode::Solid;
  thumbStyle.radius = m_thumbSize * 0.5f;
  thumbStyle.softness = 1.0f;
  thumbStyle.borderWidth = 0.0f;
  thumbStyle.fill = thumbColor;
  m_thumb->setStyle(thumbStyle);

  // Padding keeps Flex size consistent regardless of thumb position
  const float rightPad = m_inset + m_travel - (thumbX - m_inset);
  setPadding(m_inset, rightPad, m_inset, thumbX);

  if (m_enabled) {
    setOpacity(1.0f);
  } else {
    setOpacity(0.55f);
  }
}
