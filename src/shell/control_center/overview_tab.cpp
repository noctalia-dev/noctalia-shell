#include "shell/control_center/overview_tab.h"

#include "ui/controls/flex.h"

#include <cstdlib>
#include <memory>

using namespace control_center;

std::unique_ptr<Flex> OverviewTab::create() {
  const float scale = contentScale();
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceSm * scale);

  auto userCard = std::make_unique<Flex>();
  applyCard(*userCard, scale);
  const char* user = std::getenv("USER");
  addTitle(*userCard, "User", scale);
  addBody(*userCard, user != nullptr ? user : "Unknown user", scale);
  tab->addChild(std::move(userCard));

  auto mediaCard = std::make_unique<Flex>();
  applyCard(*mediaCard, scale);
  addTitle(*mediaCard, "Media", scale);
  addBody(*mediaCard, "No active session", scale);
  tab->addChild(std::move(mediaCard));

  auto weatherCard = std::make_unique<Flex>();
  applyCard(*weatherCard, scale);
  addTitle(*weatherCard, "Weather", scale);
  addBody(*weatherCard, "Not implemented yet", scale);
  tab->addChild(std::move(weatherCard));

  auto systemCard = std::make_unique<Flex>();
  applyCard(*systemCard, scale);
  addTitle(*systemCard, "System Monitor", scale);
  addBody(*systemCard, "CPU / RAM overview coming soon", scale);
  tab->addChild(std::move(systemCard));

  return tab;
}
