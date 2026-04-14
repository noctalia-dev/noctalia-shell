#include "core/ui_phase.h"
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

constexpr float kNotificationListRightPadding = Style::spaceSm;
constexpr float kNotificationActionButtonSize = Style::controlHeightSm;
constexpr int kSummaryMaxLines = 2;
constexpr int kBodyMaxLines = 3;
constexpr int kExpandedMaxLines = 500;

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
  card.setGap(Style::spaceSm * scale);
  card.setPadding((Style::spaceSm + Style::spaceXs) * scale, Style::spaceMd * scale);
  card.setRadius(Style::radiusXl * scale);
  card.setBackground(roleColor(ColorRole::SurfaceVariant, 0.9f));
  card.setBorderWidth(Style::borderWidth);
  card.setBorderColor(roleColor(ColorRole::Outline, 0.85f));
  card.setSoftness(1.25f);
}

bool canExpandText(Renderer& renderer, std::string_view text, float fontSize, bool bold, float maxWidth,
                   int collapsedMaxLines) {
  if (text.empty()) {
    return false;
  }

  const auto collapsed = renderer.measureText(text, fontSize, bold, maxWidth, collapsedMaxLines);
  const auto expanded = renderer.measureText(text, fontSize, bold, maxWidth, kExpandedMaxLines);
  const float collapsedHeight = collapsed.bottom - collapsed.top;
  const float expandedHeight = expanded.bottom - expanded.top;
  return expandedHeight > collapsedHeight + 0.5f;
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

  auto scroll = std::make_unique<ScrollView>();
  scroll->setScrollbarVisible(true);
  scroll->clearBackgroundStyle();
  scroll->setFlexGrow(1.0f);
  m_scroll = scroll.get();
  m_list = scroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Stretch);
  m_list->setGap(Style::spaceMd * scale);
  m_list->setPadding(0.0f, kNotificationListRightPadding * scale, 0.0f, 0.0f);
  tab->addChild(std::move(scroll));

  return tab;
}

std::unique_ptr<Flex> NotificationsTab::createHeaderActions() {
  const float scale = contentScale();
  auto actions = std::make_unique<Flex>();
  actions->setDirection(FlexDirection::Horizontal);
  actions->setAlign(FlexAlign::Center);
  actions->setGap(Style::spaceSm * scale);

  auto clearAll = std::make_unique<Button>();
  clearAll->setGlyph("trash");
  clearAll->setVariant(ButtonVariant::Destructive);
  clearAll->setGlyphSize(Style::fontSizeBody * scale);
  clearAll->setMinWidth(Style::controlHeightSm * scale);
  clearAll->setMinHeight(Style::controlHeightSm * scale);
  clearAll->setPadding(Style::spaceXs * scale);
  clearAll->setOnClick([this]() { clearAllNotifications(); });
  m_clearAllButton = clearAll.get();
  actions->addChild(std::move(clearAll));

  return actions;
}

void NotificationsTab::doLayout(Renderer& renderer, float contentWidth, float bodyHeight) {
  if (m_root == nullptr || m_scroll == nullptr) {
    return;
  }

  m_root->setSize(contentWidth, bodyHeight);
  m_root->layout(renderer);
  const float initialWidth = m_scroll->contentViewportWidth();
  rebuild(renderer, initialWidth);
  m_scroll->layout(renderer);

  const float settledWidth = m_scroll->contentViewportWidth();
  if (std::abs(settledWidth - initialWidth) >= 0.5f) {
    rebuild(renderer, settledWidth);
    m_scroll->layout(renderer);
  }
}

void NotificationsTab::doUpdate(Renderer& renderer) {
  if (m_scroll == nullptr) {
    return;
  }

  const float initialWidth = m_scroll->contentViewportWidth();
  rebuild(renderer, initialWidth);
  m_scroll->layout(renderer);

  const float settledWidth = m_scroll->contentViewportWidth();
  if (std::abs(settledWidth - initialWidth) >= 0.5f) {
    rebuild(renderer, settledWidth);
    m_scroll->layout(renderer);
  }
}

void NotificationsTab::onClose() {
  m_root = nullptr;
  m_scroll = nullptr;
  m_list = nullptr;
  m_clearAllButton = nullptr;
  m_expandedIds.clear();
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
  m_expandedIds.clear();
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
  m_expandedIds.erase(id);
  PanelManager::instance().refresh();
}

void NotificationsTab::toggleNotificationExpanded(uint32_t id) {
  if (m_expandedIds.contains(id)) {
    m_expandedIds.erase(id);
  } else {
    m_expandedIds.insert(id);
  }
  m_lastWidth = -1.0f;
  PanelManager::instance().refresh();
}

void NotificationsTab::rebuild(Renderer& renderer, float width) {
  uiAssertNotRendering("NotificationsTab::rebuild");
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
  const float actionButtonSize = kNotificationActionButtonSize * scale;
  const float actionButtonsGap = Style::spaceXs * scale;
  const float cardHorizontalPadding = Style::spaceMd * scale * 2.0f;
  const float cardTextWidth = std::max(0.0f, cardWidth - cardHorizontalPadding);

  if (m_notifications == nullptr || m_notifications->history().empty()) {
    auto empty = std::make_unique<Flex>();
    applyNotificationCardStyle(*empty, scale);
    empty->setAlign(FlexAlign::Center);
    empty->setGap(Style::spaceSm * scale);
    empty->setPadding(Style::spaceLg * scale, Style::spaceMd * scale);
    empty->setMinWidth(cardWidth);

    auto title = std::make_unique<Label>();
    title->setText("No notifications");
    title->setBold(true);
    title->setFontSize(Style::fontSizeBody * scale);
    title->setColor(roleColor(ColorRole::OnSurface));
    empty->addChild(std::move(title));

    auto body = std::make_unique<Label>();
    body->setText("Recent notifications will show here.");
    body->setCaptionStyle();
    body->setFontSize(Style::fontSizeCaption * scale);
    body->setColor(roleColor(ColorRole::OnSurfaceVariant));
    empty->addChild(std::move(body));

    m_list->addChild(std::move(empty));
    m_lastSerial = serial;
    m_lastWidth = width;
    return;
  }

  for (auto it = m_notifications->history().rbegin(); it != m_notifications->history().rend(); ++it) {
    const std::string summaryText =
        it->notification.summary.empty() ? "Untitled notification" : it->notification.summary;
    const std::string& bodyText = it->notification.body;
    const bool summaryExpandable =
        canExpandText(renderer, summaryText, Style::fontSizeBody * scale, true, cardTextWidth, kSummaryMaxLines);
    const bool bodyExpandable =
        canExpandText(renderer, bodyText, Style::fontSizeBody * scale, false, cardTextWidth, kBodyMaxLines);
    const bool canExpand = summaryExpandable || bodyExpandable;
    const bool expanded = canExpand && m_expandedIds.contains(it->notification.id);
    if (!canExpand) {
      m_expandedIds.erase(it->notification.id);
    }

    const float headerActionsWidth = actionButtonSize + (canExpand ? (actionButtonsGap + actionButtonSize) : 0.0f);
    const float metaTextWidth = std::max(0.0f, cardTextWidth - headerActionsWidth - Style::spaceSm * scale);

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

    auto headerActions = std::make_unique<Flex>();
    headerActions->setDirection(FlexDirection::Horizontal);
    headerActions->setAlign(FlexAlign::Center);
    headerActions->setGap(actionButtonsGap);

    if (canExpand) {
      auto expand = std::make_unique<Button>();
      expand->setGlyph(expanded ? "chevron-up" : "chevron-down");
      expand->setVariant(ButtonVariant::Ghost);
      expand->setGlyphSize(Style::fontSizeBody * scale);
      expand->setMinWidth(actionButtonSize);
      expand->setMinHeight(actionButtonSize);
      expand->setPadding(Style::spaceXs * scale);
      expand->setRadius(Style::radiusMd * scale);
      expand->setOnClick([this, id = it->notification.id]() { toggleNotificationExpanded(id); });
      headerActions->addChild(std::move(expand));
    }

    auto dismiss = std::make_unique<Button>();
    dismiss->setGlyph("trash");
    dismiss->setVariant(ButtonVariant::Ghost);
    dismiss->setGlyphSize(Style::fontSizeBody * scale);
    dismiss->setMinWidth(actionButtonSize);
    dismiss->setMinHeight(actionButtonSize);
    dismiss->setPadding(Style::spaceXs * scale);
    dismiss->setRadius(Style::radiusMd * scale);
    dismiss->setOnClick([this, id = it->notification.id, active = it->active]() {
      removeNotificationEntry(id, active);
    });
    headerActions->addChild(std::move(dismiss));
    header->addChild(std::move(headerActions));
    card->addChild(std::move(header));

    auto summary = std::make_unique<Label>();
    summary->setText(summaryText);
    summary->setBold(true);
    summary->setFontSize(Style::fontSizeTitle * scale);
    summary->setMaxWidth(cardTextWidth);
    summary->setMaxLines(expanded ? kExpandedMaxLines : kSummaryMaxLines);
    summary->measure(renderer);
    card->addChild(std::move(summary));

    if (!bodyText.empty()) {
      auto body = std::make_unique<Label>();
      body->setText(bodyText);
      body->setFontSize(Style::fontSizeCaption * scale);
      body->setColor(roleColor(ColorRole::OnSurfaceVariant));
      body->setMaxWidth(cardTextWidth);
      body->setMaxLines(expanded ? kExpandedMaxLines : kBodyMaxLines);
      body->measure(renderer);
      card->addChild(std::move(body));
    }

    m_list->addChild(std::move(card));
  }

  m_lastSerial = serial;
  m_lastWidth = width;
}
