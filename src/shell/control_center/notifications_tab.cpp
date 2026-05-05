#include "shell/control_center/notifications_tab.h"

#include "i18n/i18n.h"
#include "net/uri.h"
#include "notification/notification.h"
#include "notification/notification_manager.h"
#include "render/core/renderer.h"
#include "render/core/texture_manager.h"
#include "shell/panel/panel_manager.h"
#include "time/time_format.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/scroll_view.h"
#include "ui/controls/segmented.h"
#include "ui/controls/virtual_list_view.h"
#include "ui/palette.h"
#include "util/string_utils.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <ctime>
#include <filesystem>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unistd.h>
#include <utility>
#include <vector>

using namespace control_center;

namespace {

  constexpr float kHistoryIconSize = 36.0f;
  constexpr float kHistoryIconRadius = 8.0f;
  constexpr float kHistoryIconGlyphSize = 22.0f;

  constexpr float kNotificationActionButtonSize = Style::controlHeightSm;
  constexpr int kSummaryMaxLines = 2;
  constexpr int kBodyMaxLines = 3;
  constexpr int kExpandedMaxLines = 500;

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

  std::int64_t currentRelativeTimeSlot() {
    return std::chrono::duration_cast<std::chrono::seconds>(std::chrono::system_clock::now().time_since_epoch())
               .count() /
           15;
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
    return !isToday && !isYesterday;
  }

  float measuredTextHeight(Renderer& renderer, std::string_view text, float fontSize, bool bold, float maxWidth,
                           int maxLines) {
    if (text.empty()) {
      return 0.0f;
    }
    const auto bounds = renderer.measureText(text, fontSize, bold, maxWidth, maxLines);
    return std::max(0.0f, bounds.bottom - bounds.top);
  }

  bool canExpandText(Renderer& renderer, std::string_view text, float fontSize, bool bold, float maxWidth,
                     int collapsedMaxLines) {
    if (text.empty()) {
      return false;
    }

    const float collapsedHeight = measuredTextHeight(renderer, text, fontSize, bold, maxWidth, collapsedMaxLines);
    const float expandedHeight = measuredTextHeight(renderer, text, fontSize, bold, maxWidth, kExpandedMaxLines);
    return expandedHeight > collapsedHeight + 0.5f;
  }

  struct NotificationCardMetrics {
    std::string summaryText;
    std::string bodyText;
    std::string metaLine;
    bool canExpand = false;
    bool expanded = false;
    float height = 0.0f;
    float cardTextWidth = 0.0f;
    float metaTextWidth = 0.0f;
  };

  NotificationCardMetrics measureNotificationCard(Renderer& renderer, const NotificationHistoryEntry& entry,
                                                  float scale, float width, bool expandedRequested) {
    const auto truncateByLines = [](std::string_view text, int maxLines, bool* didTruncate) {
      if (didTruncate != nullptr) {
        *didTruncate = false;
      }
      if (maxLines <= 0 || text.empty()) {
        return std::string(text);
      }

      int seenLines = 1;
      std::size_t index = 0;
      while (index < text.size()) {
        if (text[index] == '\n') {
          ++seenLines;
          if (seenLines > maxLines) {
            if (didTruncate != nullptr) {
              *didTruncate = true;
            }
            return std::string(text.substr(0, index));
          }
        }
        ++index;
      }
      return std::string(text);
    };

    NotificationCardMetrics metrics;
    const float cardWidth = std::max(0.0f, width);
    const float cardHorizontalPadding = Style::spaceMd * scale * 2.0f;
    metrics.cardTextWidth = std::max(0.0f, cardWidth - cardHorizontalPadding);
    const std::string summaryText = StringUtils::trimLeadingBlankLines(
        entry.notification.summary.empty() ? i18n::tr("control-center.notifications.untitled")
                                           : entry.notification.summary);
    const std::string bodyText = StringUtils::trimLeadingBlankLines(entry.notification.body);
    metrics.summaryText = summaryText;

    const bool summaryExpandable = canExpandText(renderer, summaryText, Style::fontSizeBody * scale, true,
                                                 metrics.cardTextWidth, kSummaryMaxLines);
    bool bodyLineTruncated = false;
    const std::string collapsedBodyText = truncateByLines(bodyText, kBodyMaxLines, &bodyLineTruncated);
    const bool bodyExpandable = bodyLineTruncated || canExpandText(renderer, bodyText, Style::fontSizeCaption * scale,
                                                                   false, metrics.cardTextWidth, kBodyMaxLines);
    metrics.canExpand = summaryExpandable || bodyExpandable;
    metrics.expanded = metrics.canExpand && expandedRequested;
    metrics.bodyText = metrics.expanded ? bodyText : collapsedBodyText;

    const float iconPx = kHistoryIconSize * scale;
    const float iconColumn = iconPx + Style::spaceSm * scale;
    const float actionButtonSize = kNotificationActionButtonSize * scale;
    const float actionButtonsGap = Style::spaceXs * scale;
    const float headerActionsWidth =
        actionButtonSize + (metrics.canExpand ? (actionButtonsGap + actionButtonSize) : 0.0f);
    const float leftClusterWidth = metrics.cardTextWidth - headerActionsWidth;
    metrics.metaTextWidth = std::max(0.0f, leftClusterWidth - iconColumn);

    metrics.metaLine = entry.notification.appName + " • " + relativeMetaLine(entry.notification);
    if (!entry.active) {
      metrics.metaLine += " • ";
      metrics.metaLine += statusText(entry);
    }

    const float metaHeight =
        measuredTextHeight(renderer, metrics.metaLine, Style::fontSizeCaption * scale, false, metrics.metaTextWidth, 0);
    const float headerHeight = std::max({iconPx, actionButtonSize, metaHeight});
    const float summaryHeight =
        measuredTextHeight(renderer, metrics.summaryText, Style::fontSizeBody * scale, true, metrics.cardTextWidth,
                           metrics.expanded ? kExpandedMaxLines : kSummaryMaxLines);
    const float bodyHeight =
        metrics.bodyText.empty()
            ? 0.0f
            : measuredTextHeight(renderer, metrics.bodyText, Style::fontSizeCaption * scale, false,
                                 metrics.cardTextWidth, metrics.expanded ? kExpandedMaxLines : kBodyMaxLines);

    const float paddingY = (Style::spaceSm + Style::spaceXs) * scale * 2.0f;
    const int childCount = metrics.bodyText.empty() ? 2 : 3;
    const float gaps = Style::spaceSm * scale * static_cast<float>(childCount - 1);
    metrics.height = paddingY + headerHeight + summaryHeight + bodyHeight + gaps;
    return metrics;
  }

  std::uint64_t rawImageKey(const NotificationHistoryEntry& entry) {
    return (static_cast<std::uint64_t>(entry.notification.id) << 32U) ^ entry.eventSerial;
  }

  std::uint64_t revisionForEntry(const NotificationHistoryEntry& entry, bool expanded, std::int64_t relativeSlot) {
    std::uint64_t revision = entry.eventSerial;
    revision ^= static_cast<std::uint64_t>(relativeSlot < 0 ? 0 : relativeSlot) * 0x9E3779B185EBCA87ULL;
    if (expanded) {
      revision ^= 0xD1B54A32D192ED03ULL;
    }
    return revision;
  }

  class NotificationHistoryRow final : public Flex {
  public:
    explicit NotificationHistoryRow(float scale) : m_scale(scale) {
      applyNotificationCardStyle(*this, scale);
      setFillWidth(true);

      auto header = std::make_unique<Flex>();
      header->setDirection(FlexDirection::Horizontal);
      header->setAlign(FlexAlign::Center);
      header->setJustify(FlexJustify::SpaceBetween);
      header->setGap(Style::spaceSm * scale);
      m_header = static_cast<Flex*>(addChild(std::move(header)));

      auto leftCluster = std::make_unique<Flex>();
      leftCluster->setDirection(FlexDirection::Horizontal);
      leftCluster->setAlign(FlexAlign::Center);
      leftCluster->setGap(Style::spaceSm * scale);
      leftCluster->setFlexGrow(1.0f);
      m_leftCluster = static_cast<Flex*>(m_header->addChild(std::move(leftCluster)));

      auto iconSlot = std::make_unique<Box>();
      iconSlot->setSize(kHistoryIconSize * scale, kHistoryIconSize * scale);
      m_iconSlot = static_cast<Box*>(m_leftCluster->addChild(std::move(iconSlot)));

      auto image = std::make_unique<Image>();
      image->setVisible(false);
      m_image = static_cast<Image*>(m_iconSlot->addChild(std::move(image)));

      auto fallback = std::make_unique<Glyph>();
      fallback->setGlyph("bell");
      fallback->setVisible(false);
      m_fallback = static_cast<Glyph*>(m_iconSlot->addChild(std::move(fallback)));

      auto meta = std::make_unique<Label>();
      meta->setCaptionStyle();
      meta->setFontSize(Style::fontSizeCaption * scale);
      meta->setFlexGrow(1.0f);
      m_meta = static_cast<Label*>(m_leftCluster->addChild(std::move(meta)));

      auto headerActions = std::make_unique<Flex>();
      headerActions->setDirection(FlexDirection::Horizontal);
      headerActions->setAlign(FlexAlign::Center);
      headerActions->setGap(Style::spaceXs * scale);
      m_headerActions = static_cast<Flex*>(m_header->addChild(std::move(headerActions)));

      m_expand = static_cast<Button*>(m_headerActions->addChild(makeActionButton("chevron-down", scale)));
      m_dismiss = static_cast<Button*>(m_headerActions->addChild(makeActionButton("trash", scale)));

      auto summary = std::make_unique<Label>();
      summary->setBold(true);
      summary->setFontSize(Style::fontSizeBody * scale);
      m_summary = static_cast<Label*>(addChild(std::move(summary)));

      auto body = std::make_unique<Label>();
      body->setFontSize(Style::fontSizeCaption * scale);
      body->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      body->setVisible(false);
      m_body = static_cast<Label*>(addChild(std::move(body)));
    }

    void bind(Renderer& renderer, const NotificationHistoryEntry& entry, float width, bool expanded,
              IconResolver& iconResolver, std::function<void(uint32_t)> onToggleExpanded,
              std::function<void(uint32_t, bool)> onRemove) {
      const NotificationCardMetrics metrics = measureNotificationCard(renderer, entry, m_scale, width, expanded);
      setMinWidth(width);
      setSize(width, metrics.height);

      const float iconPx = kHistoryIconSize * m_scale;
      m_iconSlot->setSize(iconPx, iconPx);

      bindIcon(renderer, entry, iconResolver);

      m_meta->setText(metrics.metaLine);
      m_meta->setColor(colorSpecFromRole(statusColorRole(entry)));
      m_meta->setMaxWidth(metrics.metaTextWidth);
      m_meta->measure(renderer);

      m_expand->setVisible(metrics.canExpand);
      m_expand->setEnabled(metrics.canExpand);
      m_expand->setGlyph(metrics.expanded ? "chevron-up" : "chevron-down");
      m_expand->setOnClick(
          [onToggleExpanded = std::move(onToggleExpanded), id = entry.notification.id]() { onToggleExpanded(id); });

      m_dismiss->setOnClick([onRemove = std::move(onRemove), id = entry.notification.id, active = entry.active]() {
        onRemove(id, active);
      });

      m_summary->setText(metrics.summaryText);
      m_summary->setMaxWidth(metrics.cardTextWidth);
      m_summary->setMaxLines(metrics.expanded ? kExpandedMaxLines : kSummaryMaxLines);
      m_summary->measure(renderer);

      if (metrics.bodyText.empty()) {
        m_body->setVisible(false);
        m_body->setText("");
      } else {
        m_body->setVisible(true);
        m_body->setText(metrics.bodyText);
        m_body->setMaxWidth(metrics.cardTextWidth);
        m_body->setMaxLines(metrics.expanded ? kExpandedMaxLines : kBodyMaxLines);
        m_body->measure(renderer);
      }
    }

  private:
    enum class ImageKind {
      None,
      File,
      Raw,
    };

    static std::unique_ptr<Button> makeActionButton(std::string_view glyph, float scale) {
      auto button = std::make_unique<Button>();
      button->setGlyph(glyph);
      button->setVariant(ButtonVariant::Ghost);
      button->setGlyphSize(Style::fontSizeBody * scale);
      button->setMinWidth(kNotificationActionButtonSize * scale);
      button->setMinHeight(kNotificationActionButtonSize * scale);
      button->setPadding(Style::spaceXs * scale);
      button->setRadius(Style::radiusMd * scale);
      return button;
    }

    void showFallbackIcon(Renderer& renderer) {
      if (m_imageKind != ImageKind::None) {
        m_image->clear(renderer);
      }
      m_imageKind = ImageKind::None;
      m_rawImageKey = 0;
      m_image->setVisible(false);

      const float iconPx = kHistoryIconSize * m_scale;
      m_fallback->setGlyph("bell");
      m_fallback->setGlyphSize(kHistoryIconGlyphSize * m_scale);
      m_fallback->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
      m_fallback->measure(renderer);
      m_fallback->setPosition(std::round((iconPx - m_fallback->width()) * 0.5f),
                              std::round((iconPx - m_fallback->height()) * 0.5f));
      m_fallback->setVisible(true);
    }

    void bindIcon(Renderer& renderer, const NotificationHistoryEntry& entry, IconResolver& iconResolver) {
      const float iconPx = kHistoryIconSize * m_scale;
      m_image->setSize(iconPx, iconPx);
      m_image->setPosition(0.0f, 0.0f);
      m_image->setRadius(kHistoryIconRadius * m_scale);
      m_image->setFit(ImageFit::Cover);

      const std::string iconPath = resolveHistoryIconPath(entry.notification, iconResolver);
      if (!iconPath.empty()) {
        const int targetSize = static_cast<int>(std::round(iconPx));
        const bool ready = m_image->setSourceFile(renderer, iconPath, targetSize);
        if (ready) {
          m_imageKind = ImageKind::File;
          m_rawImageKey = 0;
          m_image->setVisible(true);
          m_fallback->setVisible(false);
          return;
        }
      }

      if (entry.notification.imageData.has_value()) {
        const auto& image = *entry.notification.imageData;
        if (image.width > 0 && image.height > 0 && !image.data.empty()) {
          const bool validImageMetadata = image.bitsPerSample == 8 && ((image.channels == 4 && image.hasAlpha) ||
                                                                       (image.channels == 3 && !image.hasAlpha));
          const PixmapFormat format = image.channels == 3 ? PixmapFormat::RGB : PixmapFormat::RGBA;
          const std::uint64_t key = rawImageKey(entry);
          bool ready = m_imageKind == ImageKind::Raw && m_rawImageKey == key && m_image->hasImage();
          if (!ready && validImageMetadata) {
            ready = m_image->setSourceRaw(renderer, image.data.data(), image.data.size(), image.width, image.height,
                                          image.rowStride, format, true);
          }
          if (ready) {
            m_imageKind = ImageKind::Raw;
            m_rawImageKey = key;
            m_image->setVisible(true);
            m_fallback->setVisible(false);
            return;
          }
        }
      }

      showFallbackIcon(renderer);
    }

    float m_scale = 1.0f;
    Flex* m_header = nullptr;
    Flex* m_leftCluster = nullptr;
    Box* m_iconSlot = nullptr;
    Image* m_image = nullptr;
    Glyph* m_fallback = nullptr;
    Label* m_meta = nullptr;
    Flex* m_headerActions = nullptr;
    Button* m_expand = nullptr;
    Button* m_dismiss = nullptr;
    Label* m_summary = nullptr;
    Label* m_body = nullptr;
    ImageKind m_imageKind = ImageKind::None;
    std::uint64_t m_rawImageKey = 0;
  };

} // namespace

class NotificationHistoryAdapter final : public VirtualListAdapter {
public:
  NotificationHistoryAdapter(NotificationsTab& owner, float scale) : m_owner(owner), m_scale(scale) {}

  [[nodiscard]] std::size_t itemCount() const override { return m_owner.m_filtered.size(); }

  [[nodiscard]] std::uint64_t itemKey(std::size_t index) const override {
    if (index >= m_owner.m_filtered.size() || m_owner.m_filtered[index] == nullptr) {
      return static_cast<std::uint64_t>(index);
    }
    return m_owner.m_filtered[index]->notification.id;
  }

  [[nodiscard]] std::uint64_t itemRevision(std::size_t index) const override {
    if (index >= m_owner.m_filtered.size() || m_owner.m_filtered[index] == nullptr) {
      return 0;
    }
    const auto& entry = *m_owner.m_filtered[index];
    const bool expanded = m_owner.m_expandedIds.contains(entry.notification.id);
    return revisionForEntry(entry, expanded, m_owner.m_lastRelativeTimeSlot);
  }

  [[nodiscard]] float measureItem(Renderer& renderer, std::size_t index, float width) override {
    if (index >= m_owner.m_filtered.size() || m_owner.m_filtered[index] == nullptr) {
      return 1.0f;
    }
    const auto& entry = *m_owner.m_filtered[index];
    const bool expanded = m_owner.m_expandedIds.contains(entry.notification.id);
    return measureNotificationCard(renderer, entry, m_scale, width, expanded).height;
  }

  [[nodiscard]] std::unique_ptr<Node> createItem() override {
    return std::make_unique<NotificationHistoryRow>(m_scale);
  }

  void bindItem(Renderer& renderer, Node& item, std::size_t index, float width, bool /*hovered*/) override {
    if (index >= m_owner.m_filtered.size() || m_owner.m_filtered[index] == nullptr) {
      return;
    }
    auto* row = dynamic_cast<NotificationHistoryRow*>(&item);
    if (row == nullptr) {
      return;
    }
    const auto& entry = *m_owner.m_filtered[index];
    row->bind(
        renderer, entry, width, m_owner.m_expandedIds.contains(entry.notification.id), m_owner.m_iconResolver,
        [this](uint32_t id) { m_owner.toggleNotificationExpanded(id); },
        [this](uint32_t id, bool active) { m_owner.removeNotificationEntry(id, active); });
  }

private:
  NotificationsTab& m_owner;
  float m_scale = 1.0f;
};

NotificationsTab::NotificationsTab(NotificationManager* notifications) : m_notifications(notifications) {}

NotificationsTab::~NotificationsTab() = default;

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
    m_lastRebuildFilterIndex = static_cast<std::size_t>(-1);
    if (m_list != nullptr) {
      m_list->scrollView().setScrollOffset(0.0f);
    }
    PanelManager::instance().refresh();
  });
  m_filter = filter.get();
  tab->addChild(std::move(filter));

  m_adapter = std::make_unique<NotificationHistoryAdapter>(*this, scale);

  auto list = std::make_unique<VirtualListView>();
  list->setFlexGrow(1.0f);
  list->setFillWidth(true);
  list->setFillHeight(true);
  list->setItemGap(Style::spaceMd * scale);
  list->setOverscanItems(3);
  list->setAdapter(m_adapter.get());
  m_list = static_cast<VirtualListView*>(tab->addChild(std::move(list)));

  auto empty = std::make_unique<Flex>();
  applyNotificationCardStyle(*empty, scale);
  empty->setAlign(FlexAlign::Center);
  empty->setGap(Style::spaceSm * scale);
  empty->setPadding(Style::spaceLg * scale, Style::spaceMd * scale);
  empty->setVisible(false);
  m_emptyCard = empty.get();

  auto title = std::make_unique<Label>();
  title->setBold(true);
  title->setFontSize(Style::fontSizeBody * scale);
  title->setColor(colorSpecFromRole(ColorRole::OnSurface));
  m_emptyTitle = static_cast<Label*>(empty->addChild(std::move(title)));

  auto body = std::make_unique<Label>();
  body->setCaptionStyle();
  body->setFontSize(Style::fontSizeCaption * scale);
  body->setColor(colorSpecFromRole(ColorRole::OnSurfaceVariant));
  m_emptyBody = static_cast<Label*>(empty->addChild(std::move(body)));

  tab->addChild(std::move(empty));

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
  if (m_root == nullptr || m_filter == nullptr) {
    return;
  }

  refreshDataSnapshot();
  m_root->setSize(contentWidth, bodyHeight);
  m_root->layout(renderer);
}

void NotificationsTab::doUpdate(Renderer& renderer) {
  if (refreshDataSnapshot() && m_root != nullptr) {
    m_root->layout(renderer);
  }
}

void NotificationsTab::onClose() {
  if (m_list != nullptr) {
    m_list->setAdapter(nullptr);
  }
  m_root = nullptr;
  m_list = nullptr;
  m_emptyCard = nullptr;
  m_emptyTitle = nullptr;
  m_emptyBody = nullptr;
  m_filter = nullptr;
  m_clearAllButton = nullptr;
  m_adapter.reset();
  m_filtered.clear();
  m_expandedIds.clear();
  m_lastSerial = 0;
  m_lastRelativeTimeSlot = -1;
  m_lastRebuildFilterIndex = static_cast<std::size_t>(-1);
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
  m_lastSerial = 0;
  if (m_list != nullptr) {
    m_list->notifyDataChanged();
  }
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
  m_lastSerial = 0;
  if (m_list != nullptr) {
    m_list->notifyDataChanged();
  }
  PanelManager::instance().refresh();
}

void NotificationsTab::toggleNotificationExpanded(uint32_t id) {
  if (m_expandedIds.contains(id)) {
    m_expandedIds.erase(id);
  } else {
    m_expandedIds.insert(id);
  }

  if (m_list != nullptr) {
    if (const auto index = filteredIndexForId(id); index.has_value()) {
      m_list->notifyItemChanged(*index);
    } else {
      m_list->notifyDataChanged();
    }
  }
  PanelManager::instance().refresh();
}

bool NotificationsTab::refreshDataSnapshot() {
  const bool hasHistory = m_notifications != nullptr && !m_notifications->history().empty();
  if (m_clearAllButton != nullptr) {
    m_clearAllButton->setEnabled(hasHistory);
  }

  const std::uint64_t serial = m_notifications != nullptr ? m_notifications->changeSerial() : 0;
  const std::int64_t relativeSlot = currentRelativeTimeSlot();
  const bool changed =
      serial != m_lastSerial || relativeSlot != m_lastRelativeTimeSlot || m_filterIndex != m_lastRebuildFilterIndex;
  if (!changed) {
    updateEmptyState(hasHistory, !m_filtered.empty());
    return false;
  }

  m_filtered.clear();
  if (m_notifications != nullptr) {
    m_filtered.reserve(m_notifications->history().size());
    for (auto it = m_notifications->history().rbegin(); it != m_notifications->history().rend(); ++it) {
      if (matchesHistoryFilter(*it, m_filterIndex)) {
        m_filtered.push_back(&*it);
      }
    }
  }

  m_lastSerial = serial;
  m_lastRelativeTimeSlot = relativeSlot;
  m_lastRebuildFilterIndex = m_filterIndex;

  updateEmptyState(hasHistory, !m_filtered.empty());
  if (m_list != nullptr) {
    m_list->notifyDataChanged();
  }
  return true;
}

void NotificationsTab::updateEmptyState(bool hasHistory, bool hasFiltered) {
  if (m_list != nullptr) {
    m_list->setVisible(hasFiltered);
  }
  if (m_emptyCard != nullptr) {
    m_emptyCard->setVisible(!hasFiltered);
  }

  if (m_emptyTitle == nullptr || m_emptyBody == nullptr) {
    return;
  }

  if (hasHistory) {
    m_emptyTitle->setText(i18n::tr("control-center.notifications.filter-empty-title"));
    m_emptyBody->setText(i18n::tr("control-center.notifications.filter-empty-body"));
  } else {
    m_emptyTitle->setText(i18n::tr("control-center.notifications.empty-title"));
    m_emptyBody->setText(i18n::tr("control-center.notifications.empty-body"));
  }
}

std::optional<std::size_t> NotificationsTab::filteredIndexForId(uint32_t id) const {
  for (std::size_t i = 0; i < m_filtered.size(); ++i) {
    if (m_filtered[i] != nullptr && m_filtered[i]->notification.id == id) {
      return i;
    }
  }
  return std::nullopt;
}
