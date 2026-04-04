#include "ui/controls/Button.h"

#include "render/core/Color.h"
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
