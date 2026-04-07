#include "shell/control_center/notifications_tab.h"

#include "notification/notification_manager.h"
#include "render/core/color.h"
#include "render/core/renderer.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"

#include <cmath>
#include <memory>

using namespace control_center;

namespace {

constexpr float kNotificationListRightPadding = Style::spaceXs;

std::string statusText(const NotificationHistoryEntry& entry) {
  if (entry.active) {
    return "Active";
  }
  if (!entry.closeReason.has_value()) {
    return "Closed";
  }
  switch (*entry.closeReason) {
  case CloseReason::Expired:    return "Expired";
  case CloseReason::Dismissed:  return "Dismissed";
  case CloseReason::ClosedByCall: return "Closed";
  }
  return "Closed";
}

Color statusColor(const NotificationHistoryEntry& entry) {
  if (entry.active) {
    return palette.primary;
  }
  if (entry.closeReason == CloseReason::Dismissed) {
    return palette.secondary;
  }
  return palette.onSurfaceVariant;
}

} // namespace

NotificationsTab::NotificationsTab(NotificationManager* notifications)
    : m_notifications(notifications) {}

std::unique_ptr<Flex> NotificationsTab::build(Renderer& /*renderer*/) {
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Start);
  tab->setGap(Style::spaceSm);

  auto scroll = std::make_unique<ScrollView>();
  scroll->setScrollbarVisible(true);
  scroll->setBackgroundStyle(rgba(0.0f, 0.0f, 0.0f, 0.0f), rgba(0.0f, 0.0f, 0.0f, 0.0f), 0.0f);
  m_scroll = scroll.get();
  m_list = scroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  m_list->setGap(Style::spaceSm);
  m_list->setPadding(0.0f, kNotificationListRightPadding, 0.0f, 0.0f);
  tab->addChild(std::move(scroll));

  return tab;
}

void NotificationsTab::layout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_scroll == nullptr) {
    return;
  }
  m_scroll->setSize(contentWidth, bodyHeight);
  m_scroll->layout(renderer);
  rebuild(renderer, m_scroll->contentViewportWidth());
  m_scroll->layout(renderer);
}

void NotificationsTab::update(Renderer& renderer) {
  const float width = m_scroll != nullptr ? m_scroll->contentViewportWidth() : 0.0f;
  rebuild(renderer, width);
}

void NotificationsTab::onClose() {
  m_scroll = nullptr;
  m_list = nullptr;
  m_lastSerial = 0;
  m_lastWidth = -1.0f;
}

void NotificationsTab::rebuild(Renderer& renderer, float width) {
  if (m_list == nullptr) {
    return;
  }

  const std::uint64_t serial = m_notifications != nullptr ? m_notifications->changeSerial() : 0;
  if (serial == m_lastSerial && std::abs(width - m_lastWidth) < 0.5f) {
    return;
  }

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  const float cardWidth = std::max(0.0f, width - kNotificationListRightPadding);
  if (m_notifications == nullptr || m_notifications->history().empty()) {
    auto empty = std::make_unique<Flex>();
    applyCard(*empty);
    empty->setMinWidth(cardWidth);
    addTitle(*empty, "No notifications");
    addBody(*empty, "Recent notifications will show here.");
    m_list->addChild(std::move(empty));
    m_lastSerial = serial;
    m_lastWidth = width;
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

    m_list->addChild(std::move(card));
  }

  m_lastSerial = serial;
  m_lastWidth = width;
}
