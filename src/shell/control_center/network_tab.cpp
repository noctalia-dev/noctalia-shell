#include "shell/control_center/network_tab.h"

#include "ui/controls/flex.h"

#include <memory>

using namespace control_center;

std::unique_ptr<Flex> NetworkTab::build(Renderer& /*renderer*/) {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceSm);

  auto card = std::make_unique<Flex>();
  applyCard(*card);
  addTitle(*card, "Network");
  addBody(*card, "Not implemented yet");
  tab->addChild(std::move(card));

  return tab;
}
