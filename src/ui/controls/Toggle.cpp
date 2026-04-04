#include "ui/controls/Toggle.h"

#include "render/core/Color.h"
#include "render/programs/RoundedRectProgram.h"
#include "render/scene/RectNode.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

#include <memory>

Toggle::Toggle() {
  setAlign(BoxAlign::Center);
  setDirection(BoxDirection::Horizontal);
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
  applyState();
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
    m_thumbSize = 10.0f;
    m_inset = 2.0f;
    m_travel = 8.0f;
    break;
  case ToggleSize::Medium:
    m_thumbSize = 12.0f;
    m_inset = 2.0f;
    m_travel = 10.0f;
    break;
  case ToggleSize::Large:
    m_thumbSize = 14.0f;
    m_inset = 3.0f;
    m_travel = 12.0f;
    break;
  }

  m_thumb->setSize(m_thumbSize, m_thumbSize);
  setRadius((m_thumbSize + (m_inset * 2.0f)) * 0.5f);
}

void Toggle::applyState() {
  auto thumbStyle = m_thumb->style();
  thumbStyle.fillMode = FillMode::Solid;
  thumbStyle.radius = m_thumbSize * 0.5f;
  thumbStyle.softness = 1.0f;
  thumbStyle.borderWidth = 0.0f;

  if (m_checked) {
    setPadding(m_inset, m_inset, m_inset, m_inset + m_travel);
    setBackground(palette.primary);
    thumbStyle.fill = palette.onPrimary;
    m_thumb->setPosition(m_inset + m_travel, m_inset);
  } else {
    setPadding(m_inset, m_inset + m_travel, m_inset, m_inset);
    setBackground(palette.surfaceVariant);
    thumbStyle.fill = palette.onSurfaceVariant;
    m_thumb->setPosition(m_inset, m_inset);
  }
  m_thumb->setStyle(thumbStyle);

  if (m_enabled) {
    setOpacity(1.0f);
  } else {
    setOpacity(0.55f);
  }
}
