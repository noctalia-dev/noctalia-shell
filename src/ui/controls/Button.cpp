#include "ui/controls/Button.h"

#include "render/core/Color.h"
#include "render/scene/InputArea.h"
#include "ui/controls/Label.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

#include <memory>

Button::Button() {
  setAlign(BoxAlign::Center);
  setPadding(Style::paddingV, Style::paddingH, Style::paddingV, Style::paddingH);
  setRadius(Style::radiusMd);

  auto label = std::make_unique<Label>();
  m_label = static_cast<Label*>(addChild(std::move(label)));
  applyVariant();
}

void Button::setText(std::string_view text) { m_label->setText(text); }

void Button::setFontSize(float size) { m_label->setFontSize(size); }

void Button::setOnClick(std::function<void()> callback) {
  m_onClick = std::move(callback);

  // Lazily create InputArea on first setOnClick
  if (m_inputArea == nullptr) {
    auto area = std::make_unique<InputArea>();
    area->setOnClick([this](const InputArea::PointerData& /*data*/) {
      if (m_onClick) {
        m_onClick();
      }
    });
    m_inputArea = static_cast<InputArea*>(addChild(std::move(area)));
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

  switch (m_variant) {
  case ButtonVariant::Default:
    setBackground(palette.primary);
    m_label->setColor(palette.onPrimary);
    setBorderColor(palette.outline);
    setBorderWidth(0.0f);
    break;
  case ButtonVariant::Secondary:
    setBackground(palette.secondary);
    m_label->setColor(palette.onSecondary);
    setBorderColor(palette.outline);
    setBorderWidth(0.0f);
    break;
  case ButtonVariant::Destructive:
    setBackground(palette.error);
    m_label->setColor(palette.onError);
    setBorderColor(palette.outline);
    setBorderWidth(0.0f);
    break;
  case ButtonVariant::Outline:
    setBackground(rgba(0.0f, 0.0f, 0.0f, 0.0f));
    m_label->setColor(palette.onSurface);
    setBorderColor(palette.outline);
    setBorderWidth(Style::borderWidth);
    break;
  case ButtonVariant::Ghost:
    setBackground(rgba(0.0f, 0.0f, 0.0f, 0.0f));
    m_label->setColor(palette.onSurface);
    setBorderWidth(0.0f);
    break;
  }
}
