#include "ui/controls/Chip.h"

#include "ui/controls/Label.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

#include <memory>

Chip::Chip() {
  setAlign(BoxAlign::Center);
  setPadding(Style::paddingV, Style::paddingH, Style::paddingV, Style::paddingH);
  setRadius(Style::radiusMd);

  auto label = std::make_unique<Label>();
  m_label = static_cast<Label*>(addChild(std::move(label)));
  m_label->setFontSize(Style::fontSizeXs);
  setWorkspaceActive(false);
}

void Chip::setText(std::string_view text) { m_label->setText(text); }

void Chip::setWorkspaceActive(bool active) {
  if (active) {
    setBackground(palette.primary);
    m_label->setColor(palette.onPrimary);
    setBorderWidth(0.0f);
  } else {
    setBackground(palette.surfaceVariant);
    m_label->setColor(palette.onSurfaceVariant);
    setBorderColor(palette.outline);
    setBorderWidth(Style::borderWidth);
  }
}
