#include "shell/control_center/network_tab.h"

#include "ui/controls/flex.h"

#include <memory>

using namespace control_center;

std::unique_ptr<Flex> NetworkTab::create() {
  const float scale = contentScale();
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceSm * scale);

  auto card = std::make_unique<Flex>();
  applyCard(*card, scale);
  addTitle(*card, "Network", scale);
  addBody(*card, "Not implemented yet", scale);
  tab->addChild(std::move(card));

  return tab;
}
