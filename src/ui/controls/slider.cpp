#include "ui/controls/slider.h"

#include "render/programs/rounded_rect_program.h"
#include "render/scene/input_area.h"
#include "render/scene/rect_node.h"
#include "ui/palette.h"
#include "ui/style.h"

#include "cursor-shape-v1-client-protocol.h"
#include <linux/input-event-codes.h>

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

constexpr float kDefaultWidth = 180.0f;
constexpr float kTrackHeight = 6.0f;
constexpr float kThumbSize = 16.0f;
constexpr float kHorizontalPadding = 2.0f;

RoundedRectStyle solidStyle(const Color& fill, float radius) {
  return RoundedRectStyle{
      .fill = fill,
      .border = fill,
      .fillMode = FillMode::Solid,
      .radius = radius,
      .softness = 1.0f,
      .borderWidth = 0.0f,
  };
}

Color resolved(ColorRole role, float alpha = 1.0f) { return resolveThemeColor(roleColor(role, alpha)); }

} // namespace

Slider::Slider() {
  auto track = std::make_unique<RectNode>();
  m_track = static_cast<RectNode*>(addChild(std::move(track)));

  auto fill = std::make_unique<RectNode>();
  m_fill = static_cast<RectNode*>(addChild(std::move(fill)));

  auto thumb = std::make_unique<RectNode>();
  m_thumb = static_cast<RectNode*>(addChild(std::move(thumb)));

  auto area = std::make_unique<InputArea>();
  area->setOnPress([this](const InputArea::PointerData& data) {
    if (!m_enabled || data.button != BTN_LEFT) {
      return;
    }
    if (!data.pressed) {
      if (m_onDragEnd) {
        m_onDragEnd();
      }
      return;
    }
    updateFromLocalX(data.localX);
  });
  area->setOnMotion([this](const InputArea::PointerData& data) {
    if (!m_enabled || m_inputArea == nullptr || !m_inputArea->pressed()) {
      return;
    }
    updateFromLocalX(data.localX);
  });
  m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));
  m_inputArea->setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);

  applyVisualState();
}

void Slider::setRange(float minValue, float maxValue) {
  if (maxValue < minValue) {
    std::swap(minValue, maxValue);
  }
  if (m_min == minValue && m_max == maxValue) {
    return;
  }
  m_min = minValue;
  m_max = maxValue;
  setValue(m_value);
}

void Slider::setStep(float step) {
  m_step = std::max(step, 0.0f);
  setValue(m_value);
}

void Slider::setValue(float value) {
  const float next = snapped(value);
  if (std::abs(next - m_value) < 0.0001f) {
    return;
  }
  m_value = next;
  updateGeometry();
  markPaintDirty();
  if (m_onValueChanged) {
    m_onValueChanged(m_value);
  }
}

void Slider::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  applyVisualState();
  markPaintDirty();
}

void Slider::setTrackHeight(float height) {
  m_trackHeight = std::max(1.0f, height);
  updateGeometry();
  markLayoutDirty();
}

void Slider::setThumbSize(float size) {
  m_thumbSizePx = std::max(1.0f, size);
  updateGeometry();
  markLayoutDirty();
}

void Slider::setControlHeight(float height) {
  m_controlHeightPx = std::max(1.0f, height);
  updateGeometry();
  markLayoutDirty();
}

void Slider::setOnValueChanged(std::function<void(float)> callback) { m_onValueChanged = std::move(callback); }

void Slider::setOnDragEnd(std::function<void()> callback) { m_onDragEnd = std::move(callback); }

bool Slider::dragging() const noexcept { return m_inputArea != nullptr && m_inputArea->pressed(); }

void Slider::doLayout(Renderer& /*renderer*/) {
  updateGeometry();
  applyVisualState();
}

void Slider::updateGeometry() {
  const float widthPx = width() > 0.0f ? width() : kDefaultWidth;
  const float heightPx = std::max({m_thumbSizePx, m_trackHeight, m_controlHeightPx});
  setSize(widthPx, heightPx);

  const float trackY = (heightPx - m_trackHeight) * 0.5f;
  const float trackX = kHorizontalPadding;
  const float trackW = std::max(0.0f, widthPx - kHorizontalPadding * 2.0f);
  const float t = normalizedValue();
  const float thumbX = trackX + t * trackW;
  const float thumbY = (heightPx - m_thumbSizePx) * 0.5f;

  m_track->setPosition(trackX, trackY);
  m_track->setSize(trackW, m_trackHeight);

  m_fill->setPosition(trackX, trackY);
  m_fill->setSize(std::max(0.0f, thumbX - trackX), m_trackHeight);

  m_thumb->setPosition(std::clamp(thumbX - m_thumbSizePx * 0.5f, trackX, trackX + trackW - m_thumbSizePx), thumbY);
  m_thumb->setSize(m_thumbSizePx, m_thumbSizePx);

  m_inputArea->setPosition(0.0f, 0.0f);
  m_inputArea->setSize(widthPx, heightPx);
}

void Slider::updateFromLocalX(float x) {
  const float widthPx = width() > 0.0f ? width() : kDefaultWidth;
  const float trackX = kHorizontalPadding;
  const float trackW = std::max(0.0f, widthPx - kHorizontalPadding * 2.0f);
  if (trackW <= 0.0f) {
    return;
  }
  const float t = std::clamp((x - trackX) / trackW, 0.0f, 1.0f);
  setValue(m_min + t * (m_max - m_min));
}

void Slider::applyVisualState() {
  const bool hovering = m_inputArea != nullptr && m_inputArea->hovered();
  const bool pressing = m_inputArea != nullptr && m_inputArea->pressed();

  Color trackColor = resolved(ColorRole::Outline);
  Color fillColor = resolved(ColorRole::Primary);
  Color thumbColor = resolved(ColorRole::Primary);
  Color thumbBorder = resolved(ColorRole::OnPrimary);

  if (!m_enabled) {
    trackColor = resolved(ColorRole::Outline, 0.5f);
    fillColor = resolved(ColorRole::Primary, 0.5f);
    thumbColor = resolved(ColorRole::Surface, 0.7f);
    thumbBorder = resolved(ColorRole::Primary, 0.6f);
  } else if (pressing) {
    thumbColor = resolved(ColorRole::Primary);
    thumbBorder = resolved(ColorRole::Primary);
  } else if (hovering) {
    thumbBorder = resolved(ColorRole::Secondary);
  }

  auto trackStyle = solidStyle(trackColor, m_trackHeight * 0.5f);
  m_track->setStyle(trackStyle);

  auto fillStyle = solidStyle(fillColor, m_trackHeight * 0.5f);
  m_fill->setStyle(fillStyle);

  auto thumbStyle = solidStyle(thumbColor, m_thumbSizePx * 0.5f);
  thumbStyle.border = thumbBorder;
  thumbStyle.borderWidth = Style::borderWidth;
  m_thumb->setStyle(thumbStyle);
}

float Slider::normalizedValue() const noexcept {
  if (m_max <= m_min) {
    return 0.0f;
  }
  return std::clamp((m_value - m_min) / (m_max - m_min), 0.0f, 1.0f);
}

float Slider::snapped(float value) const noexcept {
  const float clamped = std::clamp(value, m_min, m_max);
  if (m_step <= 0.0f || m_max <= m_min) {
    return clamped;
  }

  const float steps = std::round((clamped - m_min) / m_step);
  return std::clamp(m_min + steps * m_step, m_min, m_max);
}
