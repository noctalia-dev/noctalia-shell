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
  m_label->setStableBaseline(true);
  setActive(false);
}

void Chip::setText(std::string_view text) { m_label->setText(text); }

void Chip::setActive(bool active) {
  if (active) {
    setFill(colorSpecFromRole(ColorRole::Primary));
    m_label->setColor(colorSpecFromRole(ColorRole::OnPrimary));
    m_label->setBold(true);
    clearBorder();
  } else {
    setFill(colorSpecFromRole(ColorRole::SurfaceVariant));
    m_label->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    m_label->setBold(false);
    setBorder(colorSpecFromRole(ColorRole::Outline), Style::borderWidth);
  }
}
