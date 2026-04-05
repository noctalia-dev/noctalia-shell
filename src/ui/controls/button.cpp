#include "ui/controls/button.h"

#include "render/scene/input_area.h"
#include "ui/controls/icon.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

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
    m_icon->setSize(size);
  }
}

void Button::setIconSize(float size) {
  ensureIcon();
  m_icon->setSize(size);
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

void Button::applyVisualState() {
  bool isHovered = hovered();
  bool isPressed = pressed();

  Color labelColor;
  if (isPressed) {
    setBackground(m_bgColorPressed);
    setBorderColor(m_borderColorPressed);
    labelColor = m_labelColorPressed;
  } else if (isHovered) {
    setBackground(m_bgColorHover);
    setBorderColor(m_borderColorHover);
    labelColor = m_labelColorHover;
  } else {
    setBackground(m_bgColorNormal);
    setBorderColor(m_borderColorNormal);
    labelColor = m_labelColorNormal;
  }

  m_label->setColor(labelColor);
  if (m_icon != nullptr) {
    m_icon->setColor(labelColor);
  }
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

  // Center label when there's no icon
  if (m_icon == nullptr) {
    m_label->setPosition((width() - m_label->width()) * 0.5f, (height() - m_label->height()) * 0.5f);
  }

  if (m_inputArea != nullptr) {
    m_inputArea->setVisible(true);
    m_inputArea->setPosition(0.0f, 0.0f);
    m_inputArea->setSize(width(), height());
  }

  applyVisualState();
}
