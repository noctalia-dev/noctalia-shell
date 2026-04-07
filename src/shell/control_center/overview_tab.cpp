#include "shell/control_center/control_center_panel.h"

#include "shell/control_center/common.h"
#include "ui/controls/flex.h"

#include <cstdlib>
#include <memory>

using namespace control_center;

void ControlCenterPanel::buildOverviewTab() {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceSm);
  m_tabContainers[tabIndex(TabId::Overview)] = tab.get();

  auto userCard = std::make_unique<Flex>();
  applyCard(*userCard);
  const char* user = std::getenv("USER");
  addTitle(*userCard, "User");
  addBody(*userCard, user != nullptr ? user : "Unknown user");
  tab->addChild(std::move(userCard));

  auto mediaCard = std::make_unique<Flex>();
  applyCard(*mediaCard);
  addTitle(*mediaCard, "Media");
  addBody(*mediaCard, "No active session");
  tab->addChild(std::move(mediaCard));

  auto weatherCard = std::make_unique<Flex>();
  applyCard(*weatherCard);
  addTitle(*weatherCard, "Weather");
  addBody(*weatherCard, "Not implemented yet");
  tab->addChild(std::move(weatherCard));

  auto systemCard = std::make_unique<Flex>();
  applyCard(*systemCard);
  addTitle(*systemCard, "System Monitor");
  addBody(*systemCard, "CPU / RAM overview coming soon");
  tab->addChild(std::move(systemCard));

  m_tabBodies->addChild(std::move(tab));
}
