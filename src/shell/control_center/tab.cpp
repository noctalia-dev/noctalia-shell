#include "shell/control_center/tab.h"

#include "ui/controls/flex.h"
#include "ui/controls/label.h"

#include <memory>

namespace control_center {

void applyCard(Flex& card, float scale) {
  card.setDirection(FlexDirection::Vertical);
  card.setAlign(FlexAlign::Start);
  card.setGap(Style::spaceXs * scale);
  card.setPadding(Style::spaceSm * scale, Style::spaceMd * scale);
  card.setRadius(Style::radiusLg * scale);
  card.setBackground(roleColor(ColorRole::SurfaceVariant));
  card.setBorderWidth(0.0f);
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
