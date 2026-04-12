#include "shell/control_center/notifications_tab.h"

#include "notification/notification_manager.h"
#include "render/core/renderer.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"

#include <cmath>
#include <memory>
#include <vector>

using namespace control_center;

namespace {

constexpr float kNotificationListRightPadding = Style::spaceXs;
constexpr int kSummaryMaxLines = 2;
constexpr int kBodyMaxLines = 3;

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

ColorRole statusColorRole(const NotificationHistoryEntry& entry) {
  if (entry.active) {
    return ColorRole::Primary;
  }
  if (entry.closeReason == CloseReason::Dismissed) {
    return ColorRole::Secondary;
  }
  return ColorRole::OnSurfaceVariant;
}

void applyNotificationCardStyle(Flex& card, float scale) {
  applyCard(card, scale);
  card.setAlign(FlexAlign::Stretch);
  card.setBackground(roleColor(ColorRole::Surface));
  card.setBorderWidth(Style::borderWidth);
  card.setBorderColor(roleColor(ColorRole::Outline, 0.75f));
}

} // namespace

NotificationsTab::NotificationsTab(NotificationManager* notifications)
    : m_notifications(notifications) {}

std::unique_ptr<Flex> NotificationsTab::create() {
  const float scale = contentScale();
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceSm * scale);
  m_root = tab.get();

  auto actions = std::make_unique<Flex>();
  actions->setDirection(FlexDirection::Horizontal);
  actions->setAlign(FlexAlign::Center);
  actions->setJustify(FlexJustify::End);
  actions->setGap(Style::spaceSm * scale);

  auto clearAll = std::make_unique<Button>();
  clearAll->setText("Clear all");
  clearAll->setGlyph("trash");
  clearAll->setVariant(ButtonVariant::Default);
  clearAll->setGlyphSize(Style::fontSizeBody * scale);
  clearAll->setMinHeight(Style::controlHeightSm * scale);
  clearAll->setPadding(Style::spaceXs * scale, Style::spaceSm * scale);
  clearAll->setOnClick([this]() { clearAllNotifications(); });
  m_clearAllButton = clearAll.get();
  actions->addChild(std::move(clearAll));
  tab->addChild(std::move(actions));

  auto scroll = std::make_unique<ScrollView>();
  scroll->setScrollbarVisible(true);
  scroll->clearBackgroundStyle();
  scroll->setFlexGrow(1.0f);
  m_scroll = scroll.get();
  m_list = scroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Start);
  m_list->setGap(Style::spaceSm * scale);
  m_list->setPadding(0.0f, kNotificationListRightPadding * scale, 0.0f, 0.0f);
  tab->addChild(std::move(scroll));

  return tab;
}

void NotificationsTab::layout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_root == nullptr || m_scroll == nullptr) {
    return;
  }

  m_root->setSize(contentWidth, bodyHeight);
  m_root->layout(renderer);
  rebuild(renderer, m_scroll->contentViewportWidth());
  m_scroll->layout(renderer);
}

void NotificationsTab::update(Renderer& renderer) {
  const float width = m_scroll != nullptr ? m_scroll->contentViewportWidth() : 0.0f;
  rebuild(renderer, width);
}

void NotificationsTab::onClose() {
  m_root = nullptr;
  m_scroll = nullptr;
  m_list = nullptr;
  m_clearAllButton = nullptr;
  m_lastSerial = 0;
  m_lastWidth = -1.0f;
}

void NotificationsTab::clearAllNotifications() {
  if (m_notifications == nullptr) {
    return;
  }

  std::vector<uint32_t> activeIds;
  activeIds.reserve(m_notifications->all().size());
  for (const auto& notification : m_notifications->all()) {
    activeIds.push_back(notification.id);
  }
  for (const uint32_t id : activeIds) {
    (void)m_notifications->close(id, CloseReason::Dismissed);
  }
  m_notifications->clearHistory();
  PanelManager::instance().refresh();
}

void NotificationsTab::removeNotificationEntry(uint32_t id, bool wasActive) {
  if (m_notifications == nullptr) {
    return;
  }

  if (wasActive) {
    (void)m_notifications->close(id, CloseReason::Dismissed);
  }
  m_notifications->removeHistoryEntry(id);
  PanelManager::instance().refresh();
}

void NotificationsTab::rebuild(Renderer& renderer, float width) {
  if (m_list == nullptr) {
    return;
  }

  const bool hasHistory = m_notifications != nullptr && !m_notifications->history().empty();
  if (m_clearAllButton != nullptr) {
    m_clearAllButton->setEnabled(hasHistory);
  }

  const std::uint64_t serial = m_notifications != nullptr ? m_notifications->changeSerial() : 0;
  if (serial == m_lastSerial && std::abs(width - m_lastWidth) < 0.5f) {
    return;
  }

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  const float scale = contentScale();
  const float cardWidth = std::max(0.0f, width - kNotificationListRightPadding * scale);
  const float actionButtonSize = Style::controlHeightSm * scale;
  const float cardHorizontalPadding = Style::spaceMd * scale * 2.0f;
  const float cardTextWidth = std::max(0.0f, cardWidth - cardHorizontalPadding);
  const float metaTextWidth =
      std::max(0.0f, cardTextWidth - actionButtonSize - Style::spaceSm * scale);

  if (m_notifications == nullptr || m_notifications->history().empty()) {
    auto empty = std::make_unique<Flex>();
    applyNotificationCardStyle(*empty, scale);
    empty->setMinWidth(cardWidth);
    addTitle(*empty, "No notifications", scale);
    addBody(*empty, "Recent notifications will show here.", scale);
    m_list->addChild(std::move(empty));
    m_lastSerial = serial;
    m_lastWidth = width;
    return;
  }

  for (auto it = m_notifications->history().rbegin(); it != m_notifications->history().rend(); ++it) {
    auto card = std::make_unique<Flex>();
    applyNotificationCardStyle(*card, scale);
    card->setMinWidth(cardWidth);

    auto header = std::make_unique<Flex>();
    header->setDirection(FlexDirection::Horizontal);
    header->setAlign(FlexAlign::Center);
    header->setJustify(FlexJustify::SpaceBetween);
    header->setGap(Style::spaceSm * scale);

    auto meta = std::make_unique<Label>();
    meta->setText(it->notification.appName + " • " + statusText(*it));
    meta->setCaptionStyle();
    meta->setFontSize(Style::fontSizeCaption * scale);
    meta->setColor(roleColor(statusColorRole(*it)));
    meta->setMaxWidth(metaTextWidth);
    meta->setFlexGrow(1.0f);
    meta->measure(renderer);
    header->addChild(std::move(meta));

    auto dismiss = std::make_unique<Button>();
    dismiss->setGlyph("trash");
    dismiss->setVariant(ButtonVariant::Default);
    dismiss->setGlyphSize(Style::fontSizeBody * scale);
    dismiss->setMinWidth(actionButtonSize);
    dismiss->setMinHeight(actionButtonSize);
    dismiss->setPadding(Style::spaceSm * scale, Style::spaceMd * scale, Style::spaceSm * scale,
                        Style::spaceMd * scale);
    dismiss->setRadius(Style::radiusMd * scale);
    dismiss->setOnClick([this, id = it->notification.id, active = it->active]() {
      removeNotificationEntry(id, active);
    });
    header->addChild(std::move(dismiss));
    card->addChild(std::move(header));

    auto summary = std::make_unique<Label>();
    summary->setText(it->notification.summary.empty() ? "Untitled notification" : it->notification.summary);
    summary->setBold(true);
    summary->setFontSize(Style::fontSizeBody * scale);
    summary->setMaxWidth(cardTextWidth);
    summary->setMaxLines(kSummaryMaxLines);
    summary->measure(renderer);
    card->addChild(std::move(summary));

    if (!it->notification.body.empty()) {
      auto body = std::make_unique<Label>();
      body->setText(it->notification.body);
      body->setFontSize(Style::fontSizeBody * scale);
      body->setColor(roleColor(ColorRole::OnSurfaceVariant));
      body->setMaxWidth(cardTextWidth);
      body->setMaxLines(kBodyMaxLines);
      body->measure(renderer);
      card->addChild(std::move(body));
    }

    m_list->addChild(std::move(card));
  }

  m_lastSerial = serial;
  m_lastWidth = width;
}
