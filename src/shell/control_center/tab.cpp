#include "shell/control_center/tab.h"

#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <memory>

namespace control_center {

void applyCard(Flex& card) {
  card.setDirection(FlexDirection::Vertical);
  card.setAlign(FlexAlign::Start);
  card.setGap(Style::spaceXs);
  card.setPadding(Style::spaceSm, Style::spaceMd, Style::spaceSm, Style::spaceMd);
  card.setRadius(Style::radiusLg);
  card.setBackground(alphaSurfaceVariant(0.75f));
  card.setBorderWidth(0.0f);
  card.setSoftness(1.0f);
}

Label* addTitle(Flex& parent, const std::string& text) {
  auto label = std::make_unique<Label>();
  label->setText(text);
  label->setBold(true);
  label->setFontSize(Style::fontSizeTitle);
  label->setColor(palette.onSurface);
  auto* ptr = label.get();
  parent.addChild(std::move(label));
  return ptr;
}

void addBody(Flex& parent, const std::string& text) {
  auto label = std::make_unique<Label>();
  label->setText(text);
  label->setColor(palette.onSurfaceVariant);
  parent.addChild(std::move(label));
}

} // namespace control_center
