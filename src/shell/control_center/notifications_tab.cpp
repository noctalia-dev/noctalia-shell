#include "shell/control_center/notifications_tab.h"

#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "net/uri.h"
#include "notification/notification.h"
#include "notification/notification_manager.h"
#include "render/core/renderer.h"
#include "render/core/texture_manager.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "time/time_format.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/segmented.h"
#include "ui/palette.h"

#include <chrono>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <functional>
#include <limits>
#include <memory>
#include <string_view>
#include <unistd.h>
#include <vector>

using namespace control_center;

namespace {

  constexpr float kHistoryIconSize = 36.0f;
  constexpr float kHistoryIconRadius = 8.0f;
  constexpr float kHistoryIconGlyphSize = 22.0f;

  constexpr float kNotificationActionButtonSize = Style::controlHeightSm;

  std::filesystem::path remoteNotificationIconCachePath(std::string_view url) {
    return std::filesystem::path("/tmp") / "noctalia-notification-icons" /
           (std::to_string(std::hash<std::string_view>{}(url)) + ".img");
  }

  std::string normalizeLocalIconPath(std::string_view iconValue) { return uri::normalizeFileUrl(iconValue); }

  std::string resolveHistoryIconPath(const Notification& n, IconResolver& resolver) {
    if (!n.icon.has_value() || n.icon->empty()) {
      return {};
    }
    const std::string& iconValue = *n.icon;
    if (uri::isRemoteUrl(iconValue)) {
      const auto cached = remoteNotificationIconCachePath(iconValue);
      std::error_code ec;
      if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
        return cached.string();
      }
      return {};
    }

    const std::string localPath = normalizeLocalIconPath(iconValue);
    if (!localPath.empty() && localPath.front() == '/') {
      if (access(localPath.c_str(), R_OK) == 0) {
        return localPath;
      }
      return {};
    }
    if (localPath.empty()) {
      return {};
    }

    const std::string& resolved = resolver.resolve(localPath);
    return resolved.empty() ? std::string() : resolved;
  }
  constexpr int kSummaryMaxLines = 2;
  constexpr int kBodyMaxLines = 3;
  constexpr int kExpandedMaxLines = 500;

  std::string statusText(const NotificationHistoryEntry& entry) {
    if (entry.active) {
      return i18n::tr("control-center.notifications.status.active");
    }
    if (!entry.closeReason.has_value()) {
      return i18n::tr("control-center.notifications.status.closed");
    }
    switch (*entry.closeReason) {
    case CloseReason::Expired:
      return i18n::tr("control-center.notifications.status.expired");
    case CloseReason::Dismissed:
      return i18n::tr("control-center.notifications.status.dismissed");
    case CloseReason::ClosedByCall:
      return i18n::tr("control-center.notifications.status.closed");
    }
    return i18n::tr("control-center.notifications.status.closed");
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

  void applyNotificationCardStyle(Flex& card, float scale) { applySectionCardStyle(card, scale); }

  std::string relativeMetaLine(const Notification& n) {
    if (n.receivedWallClock.has_value()) {
      return formatTimeAgo(*n.receivedWallClock);
    }
    return formatElapsedSince(n.receivedTime);
  }

  bool matchesHistoryFilter(const NotificationHistoryEntry& e, std::size_t filterIndex) {
    if (filterIndex == 0) {
      return true;
    }
    if (!e.notification.receivedWallClock.has_value()) {
      return false;
    }
    const std::time_t entryT = WallClock::to_time_t(*e.notification.receivedWallClock);
    const std::time_t nowT = WallClock::to_time_t(WallClock::now());
    std::tm entryL{};
    std::tm nowL{};
    localtime_r(&entryT, &entryL);
    localtime_r(&nowT, &nowL);
    const bool isToday = entryL.tm_year == nowL.tm_year && entryL.tm_yday == nowL.tm_yday;
    std::tm yRef = nowL;
    yRef.tm_hour = 12;
    yRef.tm_min = 0;
    yRef.tm_sec = 0;
    yRef.tm_mday -= 1;
    mktime(&yRef);
    const bool isYesterday = entryL.tm_year == yRef.tm_year && entryL.tm_yday == yRef.tm_yday;

    if (filterIndex == 1) {
      return isToday;
    }
    if (filterIndex == 2) {
      return isYesterday;
    }
    // Older
    return !isToday && !isYesterday;
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

  std::uint64_t hashNotificationHistoryVisuals(const std::vector<const NotificationHistoryEntry*>& entries,
                                               IconResolver& resolver) {
    constexpr std::uint64_t kOffset = 14695981039346656037ULL;
    constexpr std::uint64_t kPrime = 1099511628211ULL;

    auto mix = [](std::uint64_t& hash, std::uint64_t value) {
      hash ^= value;
      hash *= kPrime;
    };

    auto mixString = [&mix](std::uint64_t& hash, std::string_view value) {
      for (unsigned char ch : value) {
        mix(hash, ch);
      }
      mix(hash, 0xffULL);
    };

    std::uint64_t hash = kOffset;
    mix(hash, IconResolver::themeGeneration());
    mix(hash, entries.size());

    for (const NotificationHistoryEntry* entry : entries) {
      if (entry == nullptr) {
        mix(hash, std::numeric_limits<std::uint64_t>::max());
        continue;
      }

      mix(hash, entry->notification.id);
      if (const std::string iconPath = resolveHistoryIconPath(entry->notification, resolver); !iconPath.empty()) {
        mixString(hash, iconPath);
      } else {
        mix(hash, 0ULL);
      }

      if (entry->notification.imageData.has_value()) {
        const auto& image = *entry->notification.imageData;
        mix(hash, 1ULL);
        mix(hash, static_cast<std::uint64_t>(std::max(0, image.width)));
        mix(hash, static_cast<std::uint64_t>(std::max(0, image.height)));
        mix(hash, static_cast<std::uint64_t>(std::max(0, image.rowStride)));
        mix(hash, static_cast<std::uint64_t>(image.channels));
        mix(hash, static_cast<std::uint64_t>(image.bitsPerSample));
        mix(hash, image.hasAlpha ? 1ULL : 0ULL);
        mix(hash, image.data.size());
      } else {
        mix(hash, 0ULL);
      }
    }

    return hash;
  }

} // namespace

NotificationsTab::NotificationsTab(NotificationManager* notifications) : m_notifications(notifications) {}

std::unique_ptr<Flex> NotificationsTab::create() {
  const float scale = contentScale();
  auto tab = std::make_unique<Flex>();
  tab->setDirection(FlexDirection::Vertical);
  tab->setAlign(FlexAlign::Stretch);
  tab->setGap(Style::spaceSm * scale);
  m_root = tab.get();

  auto filter = std::make_unique<Segmented>();
  filter->setScale(scale);
  filter->setFontSize(Style::fontSizeCaption * scale);
  filter->addOption(i18n::tr("control-center.notifications.filter.all"));
  filter->addOption(i18n::tr("control-center.notifications.filter.today"));
  filter->addOption(i18n::tr("control-center.notifications.filter.yesterday"));
  filter->addOption(i18n::tr("control-center.notifications.filter.older"));
  filter->setEqualSegmentWidths(true);
  filter->setSelectedIndex(m_filterIndex);
  filter->setOnChange([this](std::size_t idx) {
    m_filterIndex = idx;
    m_lastSerial = 0;
    PanelManager::instance().refresh();
  });
  m_filter = filter.get();
  tab->addChild(std::move(filter));

  auto scroll = std::make_unique<ScrollView>();
  scroll->setScrollbarVisible(true);
  scroll->setViewportPaddingH(0.0f);
  scroll->setViewportPaddingV(0.0f);
  scroll->clearFill();
  scroll->clearBorder();
  scroll->setFlexGrow(1.0f);
  m_scroll = scroll.get();
  m_list = scroll->content();
  m_list->setDirection(FlexDirection::Vertical);
  m_list->setAlign(FlexAlign::Stretch);
  m_list->setGap(Style::spaceMd * scale);
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
  if (m_root == nullptr || m_scroll == nullptr || m_filter == nullptr) {
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
  m_filter = nullptr;
  m_clearAllButton = nullptr;
  m_expandedIds.clear();
  m_lastSerial = 0;
  m_lastVisualSignature = 0;
  m_lastWidth = -1.0f;
  m_lastRelativeTimeSlot = -1;
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
  const std::int64_t relativeSlot =
      std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch()).count() /
      15;
  std::vector<const NotificationHistoryEntry*> filtered;
  if (m_notifications != nullptr) {
    filtered.reserve(m_notifications->history().size());
    for (auto it = m_notifications->history().rbegin(); it != m_notifications->history().rend(); ++it) {
      if (matchesHistoryFilter(*it, m_filterIndex)) {
        filtered.push_back(&*it);
      }
    }
  }

  const std::uint64_t visualSignature = hashNotificationHistoryVisuals(filtered, m_iconResolver);
  if (serial == m_lastSerial && std::abs(width - m_lastWidth) < 0.5f && relativeSlot == m_lastRelativeTimeSlot &&
      m_filterIndex == m_lastRebuildFilterIndex && visualSignature == m_lastVisualSignature) {
    return;
  }

  while (!m_list->children().empty()) {
    m_list->removeChild(m_list->children().front().get());
  }

  const float scale = contentScale();
  const float cardWidth = std::max(0.0f, width);
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
    title->setText(i18n::tr("control-center.notifications.empty-title"));
    title->setBold(true);
    title->setFontSize(Style::fontSizeBody * scale);
    title->setColor(colorSpecFromRole(ColorRole::OnSurface));
    empty->addChild(std::move(title));

    auto body = std::make_unique<Label>();
    body->setText(i18n::tr("control-center.notifications.empty-body"));
    body->setCaptionStyle();
    body->setFontSize(Style::fontSizeCaption * scale);
    body->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    empty->addChild(std::move(body));

    m_list->addChild(std::move(empty));
    m_lastSerial = serial;
    m_lastVisualSignature = visualSignature;
    m_lastWidth = width;
    m_lastRelativeTimeSlot = relativeSlot;
    m_lastRebuildFilterIndex = m_filterIndex;
    return;
  }

  if (filtered.empty()) {
    auto empty = std::make_unique<Flex>();
    applyNotificationCardStyle(*empty, scale);
    empty->setAlign(FlexAlign::Center);
    empty->setGap(Style::spaceSm * scale);
    empty->setPadding(Style::spaceLg * scale, Style::spaceMd * scale);
    empty->setMinWidth(cardWidth);

    auto title = std::make_unique<Label>();
    title->setText(i18n::tr("control-center.notifications.filter-empty-title"));
    title->setBold(true);
    title->setFontSize(Style::fontSizeBody * scale);
    title->setColor(colorSpecFromRole(ColorRole::OnSurface));
    empty->addChild(std::move(title));

    auto body = std::make_unique<Label>();
    body->setText(i18n::tr("control-center.notifications.filter-empty-body"));
    body->setCaptionStyle();
    body->setFontSize(Style::fontSizeCaption * scale);
    body->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
    empty->addChild(std::move(body));

    m_list->addChild(std::move(empty));
    m_lastSerial = serial;
    m_lastVisualSignature = visualSignature;
    m_lastWidth = width;
    m_lastRelativeTimeSlot = relativeSlot;
    m_lastRebuildFilterIndex = m_filterIndex;
    return;
  }

  for (const NotificationHistoryEntry* entry : filtered) {
    const std::string summaryText = entry->notification.summary.empty()
                                        ? i18n::tr("control-center.notifications.untitled")
                                        : entry->notification.summary;
    const std::string& bodyText = entry->notification.body;
    const bool summaryExpandable =
        canExpandText(renderer, summaryText, Style::fontSizeBody * scale, true, cardTextWidth, kSummaryMaxLines);
    const bool bodyExpandable =
        canExpandText(renderer, bodyText, Style::fontSizeBody * scale, false, cardTextWidth, kBodyMaxLines);
    const bool canExpand = summaryExpandable || bodyExpandable;
    const bool expanded = canExpand && m_expandedIds.contains(entry->notification.id);
    if (!canExpand) {
      m_expandedIds.erase(entry->notification.id);
    }

    const float iconPx = kHistoryIconSize * scale;
    const float iconColumn = iconPx + Style::spaceSm * scale;
    const float headerActionsWidth = actionButtonSize + (canExpand ? (actionButtonsGap + actionButtonSize) : 0.0f);
    const float leftClusterWidth = cardTextWidth - headerActionsWidth;
    const float metaTextWidth = std::max(0.0f, leftClusterWidth - iconColumn);

    auto card = std::make_unique<Flex>();
    applyNotificationCardStyle(*card, scale);
    card->setMinWidth(cardWidth);

    auto header = std::make_unique<Flex>();
    header->setDirection(FlexDirection::Horizontal);
    header->setAlign(FlexAlign::Center);
    header->setJustify(FlexJustify::SpaceBetween);
    header->setGap(Style::spaceSm * scale);

    auto leftCluster = std::make_unique<Flex>();
    leftCluster->setDirection(FlexDirection::Horizontal);
    leftCluster->setAlign(FlexAlign::Center);
    leftCluster->setGap(Style::spaceSm * scale);
    leftCluster->setFlexGrow(1.0f);

    auto iconSlot = std::make_unique<Node>();
    iconSlot->setSize(iconPx, iconPx);
    bool iconAssigned = false;
    const std::string iconPath = resolveHistoryIconPath(entry->notification, m_iconResolver);
    if (!iconPath.empty()) {
      auto appIcon = std::make_unique<Image>();
      appIcon->setSize(iconPx, iconPx);
      appIcon->setPosition(0.0f, 0.0f);
      appIcon->setRadius(kHistoryIconRadius * scale);
      appIcon->setFit(ImageFit::Cover);
      if (appIcon->setSourceFile(renderer, iconPath, static_cast<int>(std::round(iconPx)))) {
        iconSlot->addChild(std::move(appIcon));
        iconAssigned = true;
      }
    } else if (entry->notification.imageData.has_value()) {
      const auto& image = *entry->notification.imageData;
      if (image.width > 0 && image.height > 0 && !image.data.empty()) {
        auto appIcon = std::make_unique<Image>();
        appIcon->setSize(iconPx, iconPx);
        appIcon->setPosition(0.0f, 0.0f);
        appIcon->setRadius(kHistoryIconRadius * scale);
        appIcon->setFit(ImageFit::Cover);
        const bool validImageMetadata = image.bitsPerSample == 8 && ((image.channels == 4 && image.hasAlpha) ||
                                                                     (image.channels == 3 && !image.hasAlpha));
        const PixmapFormat format = image.channels == 3 ? PixmapFormat::RGB : PixmapFormat::RGBA;
        if (validImageMetadata && appIcon->setSourceRaw(renderer, image.data.data(), image.data.size(), image.width,
                                                        image.height, image.rowStride, format, true)) {
          iconSlot->addChild(std::move(appIcon));
          iconAssigned = true;
        }
      }
    }
    if (!iconAssigned) {
      auto fallback = std::make_unique<Glyph>();
      fallback->setGlyph("bell");
      fallback->setGlyphSize(kHistoryIconGlyphSize * scale);
      fallback->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      fallback->measure(renderer);
      fallback->setPosition(std::round((iconPx - fallback->width()) * 0.5f),
                            std::round((iconPx - fallback->height()) * 0.5f));
      iconSlot->addChild(std::move(fallback));
    }
    leftCluster->addChild(std::move(iconSlot));

    auto meta = std::make_unique<Label>();
    std::string metaLine = entry->notification.appName + " • " + relativeMetaLine(entry->notification);
    if (!entry->active) {
      metaLine += " • ";
      metaLine += statusText(*entry);
    }
    meta->setText(std::move(metaLine));
    meta->setCaptionStyle();
    meta->setFontSize(Style::fontSizeCaption * scale);
    meta->setColor(colorSpecFromRole(statusColorRole(*entry)));
    meta->setMaxWidth(metaTextWidth);
    meta->setFlexGrow(1.0f);
    meta->measure(renderer);
    leftCluster->addChild(std::move(meta));
    header->addChild(std::move(leftCluster));

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
      expand->setOnClick([this, id = entry->notification.id]() { toggleNotificationExpanded(id); });
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
    dismiss->setOnClick(
        [this, id = entry->notification.id, active = entry->active]() { removeNotificationEntry(id, active); });
    headerActions->addChild(std::move(dismiss));
    header->addChild(std::move(headerActions));
    card->addChild(std::move(header));

    auto summary = std::make_unique<Label>();
    summary->setText(summaryText);
    summary->setBold(true);
    summary->setFontSize(Style::fontSizeBody * scale);
    summary->setMaxWidth(cardTextWidth);
    summary->setMaxLines(expanded ? kExpandedMaxLines : kSummaryMaxLines);
    summary->measure(renderer);
    card->addChild(std::move(summary));

    if (!bodyText.empty()) {
      auto body = std::make_unique<Label>();
      body->setText(bodyText);
      body->setFontSize(Style::fontSizeCaption * scale);
      body->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      body->setMaxWidth(cardTextWidth);
      body->setMaxLines(expanded ? kExpandedMaxLines : kBodyMaxLines);
      body->measure(renderer);
      card->addChild(std::move(body));
    }

    m_list->addChild(std::move(card));
  }

  m_lastSerial = serial;
  m_lastVisualSignature = visualSignature;
  m_lastWidth = width;
  m_lastRelativeTimeSlot = relativeSlot;
  m_lastRebuildFilterIndex = m_filterIndex;
}
