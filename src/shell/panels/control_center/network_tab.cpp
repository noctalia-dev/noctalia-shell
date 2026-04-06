#include "shell/panels/control_center/panel.h"

#include "shell/panels/control_center/common.h"
#include "ui/controls/flex.h"

#include <memory>

using namespace control_center;

void ControlCenterPanel::buildNetworkTab() {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(static_cast<float>(Style::spaceSm));
  m_tabContainers[tabIndex(TabId::Network)] = tab.get();

  auto card = std::make_unique<Flex>();
  applyCard(*card);
  addTitle(*card, "Network");
  addBody(*card, "Not implemented yet");
  tab->addChild(std::move(card));

  m_tabBodies->addChild(std::move(tab));
}
