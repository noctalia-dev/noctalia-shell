#include "ui/controls/radio_button.h"

#include "render/scene/input_area.h"
#include "ui/controls/box.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

RadioButton::RadioButton() {
  auto outer = std::make_unique<Box>();
  m_outer = static_cast<Box*>(addChild(std::move(outer)));

  auto inner = std::make_unique<Box>();
  m_inner = static_cast<Box*>(addChild(std::move(inner)));

  auto area = std::make_unique<InputArea>();
  area->setOnEnter([this](const InputArea::PointerData& /*data*/) { applyState(); });
  area->setOnLeave([this]() { applyState(); });
  area->setOnPress([this](const InputArea::PointerData& /*data*/) { applyState(); });
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    if (!m_enabled || m_checked) {
      return;
    }
    m_checked = true;
    applyState();
    if (m_onChange) {
      m_onChange(true);
    }
  });
  m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));

  applyState();
}

void RadioButton::setChecked(bool checked) {
  if (m_checked == checked) {
    return;
  }
  m_checked = checked;
  applyState();
}

void RadioButton::setEnabled(bool enabled) {
  if (m_enabled == enabled) {
    return;
  }
  m_enabled = enabled;
  if (m_inputArea != nullptr) {
    m_inputArea->setEnabled(enabled);
  }
  applyState();
}

void RadioButton::setOnChange(std::function<void(bool)> callback) {
  m_onChange = std::move(callback);
}

bool RadioButton::hovered() const noexcept { return m_inputArea != nullptr && m_inputArea->hovered(); }

bool RadioButton::pressed() const noexcept { return m_inputArea != nullptr && m_inputArea->pressed(); }

void RadioButton::layout(Renderer& /*renderer*/) {
  const float touchSize = static_cast<float>(Style::controlHeightSm);
  const float indicatorSize = static_cast<float>(Style::fontSizeTitle + Style::spaceXs);
  const float indicatorInset = (touchSize - indicatorSize) * 0.5f;
  const float innerInset = static_cast<float>(Style::spaceXs + Style::borderWidth);
  const float innerSize = indicatorSize - innerInset * 2.0f;

  setSize(touchSize, touchSize);

  if (m_outer != nullptr) {
    m_outer->setPosition(indicatorInset, indicatorInset);
    m_outer->setSize(indicatorSize, indicatorSize);
    m_outer->setRadius(indicatorSize * 0.5f);
    m_outer->setSoftness(1.0f);
  }

  if (m_inner != nullptr) {
    m_inner->setPosition(indicatorInset + innerInset, indicatorInset + innerInset);
    m_inner->setSize(innerSize, innerSize);
    m_inner->setRadius(innerSize * 0.5f);
    m_inner->setSoftness(1.0f);
  }

  if (m_inputArea != nullptr) {
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }
}

void RadioButton::applyState() {
  if (m_outer == nullptr || m_inner == nullptr) {
    return;
  }

  Color fill = palette.surface;
  Color border = palette.outline;
  if (m_checked) {
    fill = palette.primary;
    border = palette.primary;
  } else if (pressed() || hovered()) {
    border = palette.primary;
  }

  m_outer->setFill(fill);
  m_outer->setBorder(border, static_cast<float>(Style::borderWidth));

  m_inner->setFill(m_checked ? palette.onPrimary : palette.surface);
  m_inner->setBorder(m_checked ? palette.onPrimary : palette.surface, 0.0f);
  m_inner->setVisible(m_checked);

  setOpacity(m_enabled ? 1.0f : 0.55f);
}
