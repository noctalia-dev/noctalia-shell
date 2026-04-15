#include "shell/control_center/tab.h"

#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <memory>

namespace control_center {

void applyOutlinedCard(Flex& card, float scale) {
  card.setDirection(FlexDirection::Vertical);
  card.setAlign(FlexAlign::Stretch);
  card.setGap(Style::spaceSm * scale);
  card.setPadding((Style::spaceSm + Style::spaceXs) * scale, Style::spaceMd * scale);
  card.setRadius(Style::radiusXl * scale);
  card.setBackground(roleColor(ColorRole::Surface, 0.75f));
  card.setBorderWidth(Style::borderWidth);
  card.setBorderColor(roleColor(ColorRole::Outline));
  card.setSoftness(1.0f);
}

Label* addTitle(Flex& parent, const std::string& text, float scale) {
  auto label = std::make_unique<Label>();
  label->setText(text);
  label->setBold(true);
  label->setFontSize(Style::fontSizeTitle * scale);
  label->setColor(roleColor(ColorRole::OnSurface));
  auto* ptr = label.get();
  parent.addChild(std::move(label));
  return ptr;
}

void addBody(Flex& parent, const std::string& text, float scale) {
  auto label = std::make_unique<Label>();
  label->setText(text);
  label->setFontSize(Style::fontSizeBody * scale);
  label->setColor(roleColor(ColorRole::OnSurfaceVariant));
  parent.addChild(std::move(label));
}

} // namespace control_center

std::unique_ptr<Flex> Tab::createHeaderActions() { return nullptr; }
