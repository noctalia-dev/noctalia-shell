#include "ui/controls/chip.h"

#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

Chip::Chip() {
  setAlign(FlexAlign::Center);
  setPadding(Style::spaceSm, Style::spaceMd);
  setRadius(Style::radiusMd);

  auto label = std::make_unique<Label>();
  m_label = static_cast<Label*>(addChild(std::move(label)));
  m_label->setFontSize(Style::fontSizeCaption);
  setActive(false);
}

void Chip::setText(std::string_view text) { m_label->setText(text); }

void Chip::setActive(bool active) {
  if (active) {
    setBackground(palette.primary);
    m_label->setColor(palette.onPrimary);
    m_label->setBold(true);
    setBorderWidth(0.0f);
  } else {
    setBackground(palette.surfaceVariant);
    m_label->setColor(palette.onSurfaceVariant);
    m_label->setBold(false);
    setBorderColor(palette.outline);
    setBorderWidth(Style::borderWidth);
  }
}
