#include "shell/control_center/control_center_panel.h"

#include "notification/notification_manager.h"
#include "render/core/renderer.h"
#include "shell/control_center/common.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"

#include <cmath>
#include <memory>

using namespace control_center;

void ControlCenterPanel::buildNotificationsTab() {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceSm);
  m_tabContainers[tabIndex(TabId::Notifications)] = tab.get();

  auto scroll = std::make_unique<ScrollView>();
  scroll->setScrollbarVisible(true);
  scroll->setScrollWheelStep(Style::controlHeightLg + Style::spaceSm);
  scroll->setBackgroundStyle(rgba(0.0f, 0.0f, 0.0f, 0.0f), rgba(0.0f, 0.0f, 0.0f, 0.0f), 0.0f);
  m_notificationScroll = scroll.get();
  m_notificationList = scroll->content();
  m_notificationList->setDirection(FlexDirection::Vertical);
  m_notificationList->setAlign(FlexAlign::Start);
  m_notificationList->setGap(Style::spaceSm);
  m_notificationList->setPadding(0.0f, kNotificationListRightPadding, 0.0f, 0.0f);
  tab->addChild(std::move(scroll));

  m_tabBodies->addChild(std::move(tab));
}

void ControlCenterPanel::rebuildNotifications(Renderer& renderer, float width) {
  if (m_notificationList == nullptr) {
    return;
  }

  const std::uint64_t serial = m_notifications != nullptr ? m_notifications->changeSerial() : 0;
  if (serial == m_lastNotificationSerial && std::abs(width - m_lastNotificationWidth) < 0.5f) {
    return;
  }

  while (!m_notificationList->children().empty()) {
    m_notificationList->removeChild(m_notificationList->children().front().get());
  }

  const float cardWidth = std::max(0.0f, width - kNotificationListRightPadding);
  if (m_notifications == nullptr || m_notifications->history().empty()) {
    auto empty = std::make_unique<Flex>();
    applyCard(*empty);
    empty->setMinWidth(cardWidth);
    addTitle(*empty, "No notifications");
    addBody(*empty, "Recent notifications will show here.");
    m_notificationList->addChild(std::move(empty));
    m_lastNotificationSerial = serial;
    m_lastNotificationWidth = width;
    return;
  }

  for (auto it = m_notifications->history().rbegin(); it != m_notifications->history().rend(); ++it) {
    auto card = std::make_unique<Flex>();
    applyCard(*card);
    card->setMinWidth(cardWidth);

    auto meta = std::make_unique<Label>();
    meta->setText(it->notification.appName + " • " + statusText(*it));
    meta->setCaptionStyle();
    meta->setColor(statusColor(*it));
    meta->setMaxWidth(cardWidth - Style::spaceMd * 2);
    meta->measure(renderer);
    card->addChild(std::move(meta));

    auto summary = std::make_unique<Label>();
    summary->setText(it->notification.summary.empty() ? "Untitled notification" : it->notification.summary);
    summary->setBold(true);
    summary->setMaxWidth(cardWidth - Style::spaceMd * 2);
    summary->measure(renderer);
    card->addChild(std::move(summary));

    if (!it->notification.body.empty()) {
      auto body = std::make_unique<Label>();
      body->setText(it->notification.body);
      body->setColor(palette.onSurfaceVariant);
      body->setMaxWidth(cardWidth - Style::spaceMd * 2);
      body->measure(renderer);
      card->addChild(std::move(body));
    }

    m_notificationList->addChild(std::move(card));
  }

  m_lastNotificationSerial = serial;
  m_lastNotificationWidth = width;
}
