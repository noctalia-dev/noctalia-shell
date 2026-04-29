#include "shell/notification/notification_toast.h"

#include "config/config_service.h"
#include "config/config_types.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "core/ui_phase.h"
#include "i18n/i18n.h"
#include "net/http_client.h"
#include "net/uri.h"
#include "notification/notification_manager.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "ui/controls/box.h"
#include "ui/controls/button.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/controls/progress_bar.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/surface.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <linux/input-event-codes.h>
#include <unistd.h>

namespace {

  constexpr Logger kLog("notification");

  constexpr int kCardWidth = 360;
  constexpr int kCardHeightCompact = 132;
  constexpr int kCardHeightWithActions = 170;

  constexpr float kGap = Style::spaceSm;
  constexpr float kPaddingX = Style::spaceMd;
  constexpr float kPaddingTop = 0.0f;
  constexpr float kPaddingBottom = Style::spaceMd;
  constexpr int kFallbackVisibleCards = 5;
  constexpr std::int32_t kSurfaceMargin = 8;
  constexpr float kQueuedY = -1.0f;
  constexpr float kCardInnerPad = Style::spaceMd;
  constexpr float kCloseButtonSize = 20.0f;
  constexpr float kCloseGlyphSize = 12.0f;
  constexpr float kNotificationIconSize = 42.0f;
  constexpr float kNotificationIconRadius = 10.0f;
  constexpr float kNotificationIconGlyphSize = 24.0f;
  constexpr float kIconTextGap = Style::spaceSm;
  constexpr float kActionGap = Style::spaceXs;
  constexpr float kActionRowGap = Style::spaceSm;
  constexpr int kMaxActionButtons = 2;
  std::string fallbackActionLabel() { return i18n::tr("notifications.actions.fallback"); }

  // Maps the raw DBus timeout value to a popup display duration.
  // Returns -1 to mean "persistent — never auto-dismiss".
  int resolveDisplayDuration(int32_t timeout) {
    if (timeout == 0)
      return -1;
    if (timeout == -1)
      return kDefaultNotificationTimeout;
    return std::max(1000, static_cast<int>(timeout));
  }
  constexpr int kProgressHeight = 3;
  constexpr int kContentSlideOffset = 12;                 // subtle foreground slide during reveal/retract
  constexpr float kProgressBottomMargin = Style::spaceMd; // space below progress bar to card edge
  constexpr float kBodyBottomGap = Style::spaceSm;        // gap between body text and progress bar

  constexpr float kMetaFontSize = Style::fontSizeCaption;
  constexpr float kSummaryFontSize = Style::fontSizeTitle;
  constexpr float kBodyFontSize = Style::fontSizeBody;

  constexpr float kMetaGap = Style::spaceXs;        // vertical gap between app name and summary
  constexpr float kSummaryBodyGap = Style::spaceSm; // vertical gap between summary and body

  constexpr int kMaxSummaryLines = 2;
  constexpr int kToastMaxBodyLines = 3;
  constexpr int kMaxToastCardHeight = 320;

  constexpr int kSurfaceWidth = static_cast<int>(kCardWidth + kPaddingX * 2);
  constexpr int kFallbackSurfaceHeight = static_cast<int>(
      kMaxToastCardHeight * kFallbackVisibleCards + kGap * (kFallbackVisibleCards - 1) + kPaddingTop + kPaddingBottom);

  float contentOpacityForReveal(float reveal) {
    const float v = std::clamp(reveal, 0.0f, 1.0f);
    if (v <= 0.15f) {
      return 0.0f;
    }
    return std::clamp((v - 0.15f) / 0.85f, 0.0f, 1.0f);
  }

  float contentOffsetForReveal(float reveal) {
    return std::round(static_cast<float>(kContentSlideOffset) * (1.0f - std::clamp(reveal, 0.0f, 1.0f)));
  }

  float cardRevealFromNode(const Node* cardNode) {
    if (cardNode == nullptr) {
      return 0.0f;
    }
    return std::clamp(cardNode->width() / static_cast<float>(kCardWidth), 0.0f, 1.0f);
  }

  void applyCardRevealNodes(Node* cardNode, Node* cardContent, Node* cardForeground, float reveal, float y,
                            bool revealFromLeft) {
    if (cardNode == nullptr || cardContent == nullptr || cardForeground == nullptr) {
      return;
    }

    const float clampedReveal = std::clamp(reveal, 0.0f, 1.0f);
    const float visibleWidth = std::round(static_cast<float>(kCardWidth) * clampedReveal);
    const float hiddenWidth = static_cast<float>(kCardWidth) - visibleWidth;

    const float contentSlide = contentOffsetForReveal(clampedReveal);
    if (revealFromLeft) {
      cardNode->setPosition(kPaddingX, y);
      cardNode->setSize(visibleWidth, cardNode->height());
      cardContent->setPosition(0.0f, 0.0f);
      cardForeground->setOpacity(contentOpacityForReveal(clampedReveal));
      cardForeground->setPosition(-contentSlide, 0.0f);
      return;
    }

    cardNode->setPosition(kPaddingX + hiddenWidth, y);
    cardNode->setSize(visibleWidth, cardNode->height());
    cardContent->setPosition(-hiddenWidth, 0.0f);
    cardForeground->setOpacity(contentOpacityForReveal(clampedReveal));
    cardForeground->setPosition(contentSlide, 0.0f);
  }

  float cardHeightForEntry(bool hasActions) {
    return hasActions ? static_cast<float>(kCardHeightWithActions) : static_cast<float>(kCardHeightCompact);
  }

  std::int32_t outputLogicalHeight(const WaylandOutput& output) {
    if (output.logicalHeight > 0) {
      return output.logicalHeight;
    }
    if (output.height > 0) {
      return output.height / std::max(1, output.scale);
    }
    return 0;
  }

  float bodyTopForSummary(float summaryHeight) {
    return kCardInnerPad + kCloseButtonSize + kMetaGap + summaryHeight + kSummaryBodyGap;
  }

  float availableBodyHeight(float summaryHeight, float actionsReservedHeight, float cardHeight) {
    const float progressY = cardHeight - kProgressHeight - kProgressBottomMargin;
    const float availableHeight = progressY - kBodyBottomGap - actionsReservedHeight - bodyTopForSummary(summaryHeight);
    return availableHeight;
  }

  float notificationTextStartX() { return kCardInnerPad + kNotificationIconSize + kIconTextGap; }

  float notificationTextMaxWidth() { return std::max(0.0f, kCardWidth - notificationTextStartX() - kCardInnerPad); }

  bool isBlankText(std::string_view text) {
    return text.empty() ||
           std::all_of(text.begin(), text.end(), [](unsigned char ch) { return std::isspace(ch) != 0; });
  }

  float measureActionsFromPairs(RenderContext& rc, const std::vector<std::string>& actions) {
    if (actions.empty()) {
      return 0.0f;
    }

    auto actionsRow = std::make_unique<Flex>();
    actionsRow->setDirection(FlexDirection::Horizontal);
    actionsRow->setAlign(FlexAlign::Center);
    actionsRow->setGap(kActionGap);

    int actionCount = 0;
    for (std::size_t i = 0; i + 1 < actions.size() && actionCount < kMaxActionButtons; i += 2) {
      const std::string& actionKey = actions[i];
      std::string actionLabel = actions[i + 1];
      if (isBlankText(actionLabel)) {
        actionLabel = fallbackActionLabel();
      }
      if (actionKey.empty()) {
        continue;
      }

      auto actionButton = std::make_unique<Button>();
      actionButton->setVariant(ButtonVariant::Outline);
      actionButton->setFontSize(Style::fontSizeCaption);
      actionButton->setText(actionLabel);
      actionsRow->addChild(std::move(actionButton));
      ++actionCount;
    }

    if (actionCount == 0) {
      return 0.0f;
    }

    actionsRow->layout(rc);
    return actionsRow->height() + kActionRowGap;
  }

  struct ToastGeometry {
    int summaryLines = kMaxSummaryLines;
    int bodyLines = 0;
    float summaryHeightPx = 0.0f;
    float cardHeight = 0.0f;
  };

  float requiredToastCardHeight(float summaryHeight, float bodyHeight, float actionsReserved) {
    const float bodyTop = bodyTopForSummary(summaryHeight);
    return bodyTop + bodyHeight + kBodyBottomGap + actionsReserved + static_cast<float>(kProgressHeight) +
           kProgressBottomMargin;
  }

  ToastGeometry planToastLayout(RenderContext& rc, std::string_view summary, std::string_view body,
                                const std::vector<std::string>& actions, float floorCardHeight) {
    const float textMaxWidth = notificationTextMaxWidth();
    const float actionsReserved = measureActionsFromPairs(rc, actions);
    const float maxCard = static_cast<float>(kMaxToastCardHeight);
    const float floorH = floorCardHeight;

    ToastGeometry out;

    if (isBlankText(body)) {
      Label summaryProbe;
      summaryProbe.setFontSize(kSummaryFontSize);
      summaryProbe.setBold(true);
      summaryProbe.setMaxWidth(textMaxWidth);
      summaryProbe.setText(summary);
      summaryProbe.setMaxLines(kMaxSummaryLines);
      summaryProbe.measure(rc);
      const float sumH = summaryProbe.height();
      const float required = requiredToastCardHeight(sumH, 0.0f, actionsReserved);
      out.summaryLines = kMaxSummaryLines;
      out.bodyLines = 0;
      out.summaryHeightPx = sumH;
      out.cardHeight = std::min(maxCard, std::max(floorH, std::ceil(required)));
      return out;
    }

    static constexpr std::array<std::pair<int, int>, 6> kPreference = {{
        {2, kToastMaxBodyLines},
        {2, 2},
        {2, 1},
        {1, kToastMaxBodyLines},
        {1, 2},
        {1, 1},
    }};

    for (const auto& [sl, bl] : kPreference) {
      Label summaryProbe;
      summaryProbe.setFontSize(kSummaryFontSize);
      summaryProbe.setBold(true);
      summaryProbe.setMaxWidth(textMaxWidth);
      summaryProbe.setText(summary);
      summaryProbe.setMaxLines(sl);
      summaryProbe.measure(rc);
      const float sumH = summaryProbe.height();

      Label bodyProbe;
      bodyProbe.setFontSize(kBodyFontSize);
      bodyProbe.setMaxWidth(textMaxWidth);
      bodyProbe.setText(body);
      bodyProbe.setMaxLines(bl);
      bodyProbe.measure(rc);
      const float bodyH = bodyProbe.height();

      const float required = requiredToastCardHeight(sumH, bodyH, actionsReserved);
      const float cardH = std::max(floorH, std::ceil(required));
      if (cardH <= maxCard + 0.5f) {
        out.summaryLines = sl;
        out.bodyLines = bl;
        out.summaryHeightPx = sumH;
        out.cardHeight = cardH;
        return out;
      }
    }

    Label summaryProbe;
    summaryProbe.setFontSize(kSummaryFontSize);
    summaryProbe.setBold(true);
    summaryProbe.setMaxWidth(textMaxWidth);
    summaryProbe.setText(summary);
    summaryProbe.setMaxLines(1);
    summaryProbe.measure(rc);

    Label bodyProbe;
    bodyProbe.setFontSize(kBodyFontSize);
    bodyProbe.setMaxWidth(textMaxWidth);
    bodyProbe.setText(body);
    bodyProbe.setMaxLines(1);
    bodyProbe.measure(rc);

    out.summaryLines = 1;
    out.bodyLines = 1;
    out.summaryHeightPx = summaryProbe.height();
    out.cardHeight = std::min(
        maxCard,
        std::max(floorH, std::ceil(requiredToastCardHeight(out.summaryHeightPx, bodyProbe.height(), actionsReserved))));
    return out;
  }

  void clampBodyLabelHeight(Label& bodyLabel, float maxBodyHeight) {
    if (maxBodyHeight <= 0.0f) {
      bodyLabel.setText("");
      bodyLabel.setVisible(false);
      return;
    }

    bodyLabel.setClipChildren(true);
    bodyLabel.setSize(bodyLabel.width(), std::max(1.0f, std::floor(maxBodyHeight)));
  }

  bool isRemoteIconUrl(std::string_view url) { return uri::isRemoteUrl(url); }

  std::string normalizeLocalIconPath(std::string_view iconValue) { return uri::normalizeFileUrl(iconValue); }

  bool isBottomPosition(std::string_view position) { return position.starts_with("bottom_"); }

  bool isLeftPosition(std::string_view position) { return position.ends_with("_left"); }

  std::filesystem::path remoteIconCachePath(std::string_view url) {
    const std::filesystem::path cacheDir = std::filesystem::path("/tmp") / "noctalia-notification-icons";
    const std::size_t hash = std::hash<std::string_view>{}(url);
    return cacheDir / (std::to_string(hash) + ".img");
  }

} // namespace

NotificationToast::NotificationToast() = default;

NotificationToast::~NotificationToast() {
  if (m_notifications != nullptr && m_callbackToken >= 0) {
    m_notifications->removeEventCallback(m_callbackToken);
  }
  destroySurfaces();
}

void NotificationToast::initialize(WaylandConnection& wayland, ConfigService* config,
                                   NotificationManager* notifications, RenderContext* renderContext,
                                   HttpClient* httpClient) {
  m_wayland = &wayland;
  m_config = config;
  m_notifications = notifications;
  m_renderContext = renderContext;
  m_httpClient = httpClient;

  m_callbackToken = m_notifications->addEventCallback(
      [this](const Notification& n, NotificationEvent event) { onNotificationEvent(n, event); });
}

void NotificationToast::requestLayout() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestLayout();
    }
  }
}

void NotificationToast::requestRedraw() {
  for (auto& inst : m_instances) {
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
    }
  }
}

// --- Notification events ---

void NotificationToast::onNotificationEvent(const Notification& n, NotificationEvent event) {
  switch (event) {
  case NotificationEvent::Added:
    if (m_notifications != nullptr && m_notifications->doNotDisturb()) {
      break;
    }
    addPopup(n);
    break;
  case NotificationEvent::Updated: {
    for (std::size_t i = 0; i < m_entries.size(); ++i) {
      if (m_entries[i].notificationId == n.id && !m_entries[i].exiting) {
        const bool actionSetChanged = (m_entries[i].actions != n.actions) || (m_entries[i].icon != n.icon);
        const bool imageDataChanged = (m_entries[i].imageData != n.imageData);
        const float previousHeight = m_entries[i].height;
        const int prevToastSummaryLines = m_entries[i].toastSummaryLines;
        const int prevToastBodyLines = m_entries[i].toastBodyLines;
        const bool previouslyPlaced = hasPlacement(m_entries[i]);
        m_entries[i].appName = n.appName;
        m_entries[i].summary = n.summary;
        m_entries[i].body = n.body;
        m_entries[i].actions = n.actions;
        m_entries[i].icon = n.icon;
        m_entries[i].imageData = n.imageData;
        refreshEntryGeometry(m_entries[i]);
        m_entries[i].rawTimeoutMs = n.timeout;
        const bool layoutChanged = actionSetChanged || imageDataChanged ||
                                   std::abs(previousHeight - m_entries[i].height) > 0.5f ||
                                   prevToastSummaryLines != m_entries[i].toastSummaryLines ||
                                   prevToastBodyLines != m_entries[i].toastBodyLines;
        const bool hovered = m_entries[i].hovered;

        if (previouslyPlaced) {
          if (canKeepPlacement(m_entries[i], n.id)) {
            evictOverlappingEntries(i);
            if (!canKeepPlacement(m_entries[i], n.id)) {
              m_entries[i].y = kQueuedY;
            }
          } else {
            m_entries[i].y = kQueuedY;
          }
          if (!hasPlacement(m_entries[i]) && m_entries[i].rawTimeoutMs > 0 && m_notifications != nullptr) {
            m_notifications->pauseExpiry(n.id);
          }
        }

        // Update text nodes and reset countdown on each instance
        for (auto& inst : m_instances) {
          if (i >= inst->cards.size()) {
            continue;
          }
          auto& cs = inst->cards[i];
          if (cs.cardNode == nullptr) {
            continue;
          }
          bool regionChanged = false;

          if (layoutChanged) {
            const float preservedReveal = cardReveal(cs);
            const float preservedContentOpacity = cs.cardForeground != nullptr ? cs.cardForeground->opacity() : 1.0f;

            if (cs.countdownAnimId != 0) {
              inst->animations.cancel(cs.countdownAnimId);
            }
            if (cs.entryAnimId != 0) {
              inst->animations.cancel(cs.entryAnimId);
            }
            if (cs.slideAnimId != 0) {
              inst->animations.cancel(cs.slideAnimId);
            }
            if (cs.exitAnimId != 0) {
              inst->animations.cancel(cs.exitAnimId);
            }

            if (inst->sceneRoot != nullptr) {
              inst->sceneRoot->removeChild(cs.cardNode);
            }

            cs = {};
            InputArea* rebuilt =
                buildCard(m_entries[i], &cs.cardContent, &cs.cardForeground, &cs.appNameLabel, &cs.summaryLabel,
                          &cs.bodyLabel, &cs.cardBg, &cs.appIconNode, &cs.progressBar, &cs.closeGlyph);
            cs.cardNode = rebuilt;
            applyCardReveal(cs, preservedReveal, m_entries[i].y >= 0.0f ? m_entries[i].y : 0.0f);
            if (cs.cardForeground != nullptr) {
              cs.cardForeground->setOpacity(preservedContentOpacity);
              cs.cardForeground->setPosition(contentOffsetForReveal(preservedReveal), 0.0f);
            }
            if (inst->sceneRoot != nullptr) {
              inst->sceneRoot->addChild(std::unique_ptr<Node>(rebuilt));
            }
            regionChanged = true;
          } else if (!layoutChanged) {
            cs.appNameLabel->setText(n.appName);
            const float actionsReservedHeight = measureActionsFromPairs(*m_renderContext, m_entries[i].actions);
            PopupEntry& e = m_entries[i];
            cs.summaryLabel->setText(e.summary);
            cs.summaryLabel->setMaxLines(std::max(1, e.toastSummaryLines));
            cs.summaryLabel->measure(*m_renderContext);
            const float summaryH = cs.summaryLabel->height();
            const float bodyHeight = availableBodyHeight(summaryH, actionsReservedHeight, cs.cardNode->height());
            const int bodyLines = e.toastBodyLines;
            cs.bodyLabel->setMaxLines(std::max(1, bodyLines));
            cs.bodyLabel->setText(bodyLines > 0 ? e.body : "");
            cs.bodyLabel->measure(*m_renderContext);
            cs.bodyLabel->setVisible(bodyLines > 0 && !e.body.empty());
            cs.bodyLabel->setPosition(notificationTextStartX(), bodyTopForSummary(summaryH));
            clampBodyLabelHeight(*cs.bodyLabel, bodyHeight);
          }

          // Reset countdown
          if (cs.countdownAnimId != 0) {
            inst->animations.cancel(cs.countdownAnimId);
          }
          const int newDuration = resolveDisplayDuration(n.timeout);
          m_entries[i].displayDurationMs = newDuration;
          m_entries[i].remainingProgress = 1.0f;
          if (newDuration < 0) {
            cs.progressBar->setOpacity(0.0f);
            cs.progressBar->setProgress(1.0f);
            cs.countdownAnimId = 0;
          } else {
            cs.progressBar->setOpacity(1.0f);
            cs.progressBar->setProgress(1.0f);
            if (hovered) {
              cs.countdownAnimId = 0;
            } else {
              cs.countdownAnimId = inst->animations.animateUnscaled(
                  1.0f, 0.0f, static_cast<float>(newDuration), Easing::Linear,
                  [this, pb = cs.progressBar, notificationId = n.id](float v) {
                    pb->setProgress(v);
                    if (auto* popup = findEntry(notificationId); popup != nullptr) {
                      popup->remainingProgress = v;
                    }
                  },
                  [this, id = n.id]() { DeferredCall::callLater([this, id]() { removePopup(id); }); }, cs.progressBar);
            }
          }

          // Flash
          if (cs.cardForeground != nullptr) {
            cs.cardForeground->setOpacity(0.7f);
            inst->animations.animate(
                0.7f, 1.0f, Style::animFast, Easing::EaseOutCubic,
                [content = cs.cardForeground](float v) { content->setOpacity(v); }, {}, cs.cardForeground);
          }

          // Recompute input + blur regions whenever a card node is rebuilt in place,
          // otherwise the compositor can keep stale strips from the previous geometry.
          if (regionChanged) {
            updateInputRegion(*inst);
            if (inst->pointerInside) {
              inst->inputDispatcher.pointerMotion(inst->lastPointerX, inst->lastPointerY, 0);
            }
          }
          inst->surface->requestRedraw();
        }
        if (hovered && m_notifications != nullptr) {
          m_notifications->pauseExpiry(n.id);
        }

        if (!hasPlacement(m_entries[i])) {
          syncEntryVisibility(i);
          revealQueuedEntries();
        } else if (std::abs(previousHeight - m_entries[i].height) > 0.5f) {
          syncEntryVisibility(i);
          revealQueuedEntries();
        }
        break;
      }
    }
    break;
  }
  case NotificationEvent::Closed:
    removePopup(n.id);
    break;
  }
}

void NotificationToast::addPopup(const Notification& n) {
  for (const auto& entry : m_entries) {
    if (entry.notificationId == n.id) {
      return;
    }
  }

  ensureSurfaces();

  PopupEntry entry;
  entry.notificationId = n.id;
  entry.appName = n.appName;
  entry.summary = n.summary;
  entry.body = n.body;
  entry.actions = n.actions;
  entry.icon = n.icon;
  entry.imageData = n.imageData;
  entry.urgency = n.urgency;
  entry.displayDurationMs = resolveDisplayDuration(n.timeout);
  entry.rawTimeoutMs = n.timeout;
  entry.remainingProgress = 1.0f;
  refreshEntryGeometry(entry);
  if (const auto placement = findPlacementY(entry.height); placement.has_value()) {
    entry.y = *placement;
  } else if (entry.rawTimeoutMs > 0 && m_notifications != nullptr) {
    // Queued off-screen: freeze the manager-side auto-dismiss timer so the notification
    // doesn't expire silently before a slot opens up. It will be resumed with the full
    // duration when revealQueuedEntries() places the card.
    m_notifications->pauseExpiry(n.id);
  }
  m_entries.push_back(std::move(entry));
  std::size_t index = m_entries.size() - 1;

  for (auto& inst : m_instances) {
    if (inst->sceneRoot == nullptr) {
      continue;
    }
    inst->cards.resize(m_entries.size());
  }
  syncEntryVisibility(index);
  revealQueuedEntries();

  kLog.debug("notification toast: showing #{} \"{}\"", n.id, n.summary);
}

void NotificationToast::removePopup(uint32_t notificationId) {
  for (std::size_t i = 0; i < m_entries.size(); ++i) {
    if (m_entries[i].notificationId == notificationId && !m_entries[i].exiting) {
      dismissPopup(i);
      return;
    }
  }
}

void NotificationToast::dismissPopup(std::size_t index) {
  if (index >= m_entries.size()) {
    return;
  }
  auto& entry = m_entries[index];
  if (entry.exiting) {
    return;
  }
  entry.exiting = true;

  bool hadVisibleCard = false;
  for (auto& inst : m_instances) {
    if (index < inst->cards.size() && inst->cards[index].cardNode != nullptr) {
      hadVisibleCard = true;
    }
    dismissCardFromInstance(*inst, index);
  }
  if (!hadVisibleCard) {
    finishRemoval(entry.notificationId);
  }
}

void NotificationToast::finishRemoval(uint32_t notificationId) {
  const auto it = std::find_if(m_entries.begin(), m_entries.end(), [notificationId](const PopupEntry& entry) {
    return entry.notificationId == notificationId;
  });
  if (it == m_entries.end()) {
    return;
  }
  const std::size_t index = static_cast<std::size_t>(std::distance(m_entries.begin(), it));

  // Remove card nodes from all instances
  for (auto& inst : m_instances) {
    if (index < inst->cards.size()) {
      removeCardFromInstance(*inst, index);
      inst->cards.erase(inst->cards.begin() + static_cast<std::ptrdiff_t>(index));
    }
  }

  m_entries.erase(m_entries.begin() + static_cast<std::ptrdiff_t>(index));

  if (m_entries.empty()) {
    destroySurfaces();
  } else {
    revealQueuedEntries();
  }
}

// --- Per-instance card management ---

void NotificationToast::addCardToInstance(Instance& inst, std::size_t entryIndex) {
  auto& entry = m_entries[entryIndex];
  if (!hasPlacement(entry) || !fitsOnSurface(entry, static_cast<float>(inst.surface->height()))) {
    return;
  }

  if (entryIndex >= inst.cards.size()) {
    inst.cards.resize(entryIndex + 1);
  }

  auto& cs = inst.cards[entryIndex];
  cs = {};
  InputArea* card = buildCard(entry, &cs.cardContent, &cs.cardForeground, &cs.appNameLabel, &cs.summaryLabel,
                              &cs.bodyLabel, &cs.cardBg, &cs.appIconNode, &cs.progressBar, &cs.closeGlyph);
  cs.cardNode = card;

  const float targetY = entry.y;
  applyCardReveal(cs, 0.0f, targetY);

  inst.sceneRoot->addChild(std::unique_ptr<Node>(card));

  // Entry animation
  cs.entryAnimId = inst.animations.animate(
      0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic,
      [this, viewport = cs.cardNode, content = cs.cardContent, foreground = cs.cardForeground, targetY](float v) {
        applyCardRevealNodes(viewport, content, foreground, v, targetY, revealFromLeftEdge());
      },
      [&inst, entryIndex]() {
        if (entryIndex < inst.cards.size()) {
          inst.cards[entryIndex].entryAnimId = 0;
        }
      },
      card);

  // Countdown. Every instance that hosts a card runs its own countdown animation and
  // calls removePopup when it finishes; dismissPopup's `exiting` guard dedupes. Picking
  // a single "driver" instance is unsafe because addCardToInstance skips instances
  // whose surface can't fit the card, so the nominal driver may never have a card at all.
  if (entry.displayDurationMs < 0) {
    // Persistent — no countdown, no auto-dismiss
    cs.progressBar->setOpacity(0.0f);
    cs.countdownAnimId = 0;
  } else {
    const float startProgress = std::clamp(entry.remainingProgress, 0.0f, 1.0f);
    cs.progressBar->setOpacity(1.0f);
    cs.progressBar->setProgress(startProgress);
    cs.countdownAnimId = inst.animations.animateUnscaled(
        startProgress, 0.0f, static_cast<float>(entry.displayDurationMs) * startProgress, Easing::Linear,
        [this, pb = cs.progressBar, notificationId = entry.notificationId](float v) {
          pb->setProgress(v);
          if (auto* popup = findEntry(notificationId); popup != nullptr) {
            popup->remainingProgress = v;
          }
        },
        [this, id = entry.notificationId]() { DeferredCall::callLater([this, id]() { removePopup(id); }); },
        cs.progressBar);
  }

  // Hover wiring: pause countdown while the card is hovered, and brighten the (X).
  // On leave, resume the countdown from the remaining progress.
  const bool isCritical = (entry.urgency == Urgency::Critical);
  const Color closeColorNormal =
      resolveThemeColor(isCritical ? roleColor(ColorRole::Error, 0.75f) : roleColor(ColorRole::OnSurfaceVariant, 0.6f));
  const Color closeColorHover =
      resolveThemeColor(isCritical ? roleColor(ColorRole::Error) : roleColor(ColorRole::OnSurface));
  const int totalDuration = entry.displayDurationMs;
  const uint32_t notificationId = entry.notificationId;
  Glyph* closeGlyphPtr = cs.closeGlyph;
  ProgressBar* progressBarPtr = cs.progressBar;

  card->setOnEnter(
      [this, closeGlyphPtr, closeColorHover, notificationId, progressBarPtr](const InputArea::PointerData&) {
        closeGlyphPtr->setColor(closeColorHover);
        if (auto* popup = findEntry(notificationId); popup != nullptr) {
          popup->hovered = true;
          popup->remainingProgress = std::clamp(progressBarPtr->progress(), 0.0f, 1.0f);
        }
        pauseCountdowns(notificationId);
        // Pause the server-side expiry — otherwise NotificationManager's own timer
        // would fire Closed behind our back, which is what "the progress bar stops
        // but the timer keeps running" was.
        if (m_notifications != nullptr) {
          m_notifications->pauseExpiry(notificationId);
        }
      });

  card->setOnLeave([this, notificationId, totalDuration, closeGlyphPtr, closeColorNormal, progressBarPtr]() {
    closeGlyphPtr->setColor(closeColorNormal);
    if (auto* popup = findEntry(notificationId); popup != nullptr) {
      popup->hovered = false;
      popup->remainingProgress = std::clamp(progressBarPtr->progress(), 0.0f, 1.0f);
    }
    if (totalDuration < 0) {
      return;
    }
    const float remaining = std::clamp(progressBarPtr->progress(), 0.0f, 1.0f);
    if (remaining <= 0.0f) {
      if (m_notifications != nullptr) {
        m_notifications->resumeExpiry(notificationId, 0);
      }
      return;
    }
    const int32_t remainingMs =
        std::max<int32_t>(1, static_cast<int32_t>(std::ceil(static_cast<float>(totalDuration) * remaining)));
    if (m_notifications != nullptr) {
      m_notifications->resumeExpiry(notificationId, remainingMs);
    }
    resumeCountdowns(notificationId);
  });

  updateInputRegion(inst);
  if (inst.pointerInside) {
    inst.inputDispatcher.pointerMotion(inst.lastPointerX, inst.lastPointerY, 0);
  }
  inst.surface->requestRedraw();
}

void NotificationToast::removeCardFromInstance(Instance& inst, std::size_t entryIndex) {
  if (entryIndex >= inst.cards.size()) {
    return;
  }

  auto& cs = inst.cards[entryIndex];
  if (cs.countdownAnimId != 0) {
    inst.animations.cancel(cs.countdownAnimId);
    cs.countdownAnimId = 0;
  }
  if (cs.entryAnimId != 0) {
    inst.animations.cancel(cs.entryAnimId);
    cs.entryAnimId = 0;
  }
  if (cs.slideAnimId != 0) {
    inst.animations.cancel(cs.slideAnimId);
    cs.slideAnimId = 0;
  }
  if (cs.exitAnimId != 0) {
    inst.animations.cancel(cs.exitAnimId);
    cs.exitAnimId = 0;
  }
  if (cs.cardNode == nullptr) {
    return;
  }

  if (auto* hovered = inst.inputDispatcher.hoveredArea();
      hovered != nullptr && hovered == static_cast<InputArea*>(cs.cardNode)) {
    hovered->dispatchLeave();
  }

  if (inst.sceneRoot != nullptr) {
    inst.sceneRoot->removeChild(cs.cardNode);
  }
  cs = {};

  updateInputRegion(inst);
  if (inst.pointerInside) {
    inst.inputDispatcher.pointerMotion(inst.lastPointerX, inst.lastPointerY, 0);
  }
  if (inst.surface != nullptr) {
    inst.surface->requestRedraw();
  }
}

void NotificationToast::syncEntryVisibility(std::size_t entryIndex) {
  if (entryIndex >= m_entries.size()) {
    return;
  }

  for (auto& inst : m_instances) {
    if (inst->sceneRoot == nullptr || inst->surface == nullptr) {
      continue;
    }
    if (entryIndex >= inst->cards.size()) {
      inst->cards.resize(m_entries.size());
    }

    auto& cs = inst->cards[entryIndex];
    const bool shouldShow = hasPlacement(m_entries[entryIndex]) &&
                            fitsOnSurface(m_entries[entryIndex], static_cast<float>(inst->surface->height()));
    if (shouldShow) {
      if (cs.cardNode == nullptr) {
        addCardToInstance(*inst, entryIndex);
      }
    } else if (cs.cardNode != nullptr) {
      removeCardFromInstance(*inst, entryIndex);
    }
  }
}

void NotificationToast::dismissCardFromInstance(Instance& inst, std::size_t entryIndex) {
  if (entryIndex >= inst.cards.size()) {
    return;
  }

  auto& cs = inst.cards[entryIndex];
  if (cs.countdownAnimId != 0) {
    inst.animations.cancel(cs.countdownAnimId);
    cs.countdownAnimId = 0;
  }
  if (cs.entryAnimId != 0) {
    inst.animations.cancel(cs.entryAnimId);
    cs.entryAnimId = 0;
  }
  if (cs.slideAnimId != 0) {
    inst.animations.cancel(cs.slideAnimId);
    cs.slideAnimId = 0;
  }
  if (cs.exitAnimId != 0) {
    inst.animations.cancel(cs.exitAnimId);
    cs.exitAnimId = 0;
  }
  if (cs.cardNode == nullptr) {
    return;
  }

  Node* card = cs.cardNode;
  Node* content = cs.cardContent;
  Node* foreground = cs.cardForeground;
  const float startReveal = cardReveal(cs);
  const float targetY = card->y();
  const uint32_t removingId = (entryIndex < m_entries.size()) ? m_entries[entryIndex].notificationId : 0;

  // Only the first instance drives finishRemoval
  bool isDriver = (m_instances.size() > 0 && m_instances[0].get() == &inst);
  cs.exitAnimId = inst.animations.animate(
      startReveal, 0.0f, Style::animNormal, Easing::EaseInOutQuad,
      [this, card, content, foreground, targetY](float v) {
        applyCardRevealNodes(card, content, foreground, v, targetY, revealFromLeftEdge());
      },
      [this, &inst, entryIndex, isDriver, removingId]() {
        if (entryIndex < inst.cards.size()) {
          inst.cards[entryIndex].exitAnimId = 0;
        }
        if (isDriver && removingId != 0) {
          DeferredCall::callLater([this, removingId]() { finishRemoval(removingId); });
        }
      },
      card);

  updateInputRegion(inst);
  inst.surface->requestRedraw();
}

NotificationToast::PopupEntry* NotificationToast::findEntry(uint32_t notificationId) {
  const auto it = std::find_if(m_entries.begin(), m_entries.end(), [notificationId](const PopupEntry& entry) {
    return entry.notificationId == notificationId;
  });
  if (it == m_entries.end()) {
    return nullptr;
  }
  return &*it;
}

NotificationToast::Instance::CardState* NotificationToast::findCardState(Instance& inst, uint32_t notificationId) {
  for (std::size_t i = 0; i < inst.cards.size() && i < m_entries.size(); ++i) {
    if (m_entries[i].notificationId == notificationId) {
      return &inst.cards[i];
    }
  }
  return nullptr;
}

void NotificationToast::pauseCountdowns(uint32_t notificationId) {
  auto* entry = findEntry(notificationId);
  float remaining = (entry != nullptr) ? std::clamp(entry->remainingProgress, 0.0f, 1.0f) : 1.0f;

  for (auto& inst : m_instances) {
    auto* state = findCardState(*inst, notificationId);
    if (state == nullptr) {
      continue;
    }
    if (state->progressBar != nullptr) {
      remaining = std::clamp(state->progressBar->progress(), 0.0f, 1.0f);
    }
    if (state->countdownAnimId == 0) {
      continue;
    }
    inst->animations.cancel(state->countdownAnimId);
    state->countdownAnimId = 0;
  }

  if (entry != nullptr) {
    entry->remainingProgress = remaining;
  }
}

void NotificationToast::resumeCountdowns(uint32_t notificationId) {
  auto* entry = findEntry(notificationId);
  if (entry == nullptr || entry->displayDurationMs < 0 || entry->hovered) {
    return;
  }

  const float remaining = std::clamp(entry->remainingProgress, 0.0f, 1.0f);
  if (remaining <= 0.0f) {
    return;
  }

  for (auto& inst : m_instances) {
    auto* state = findCardState(*inst, notificationId);
    if (state == nullptr || state->progressBar == nullptr) {
      continue;
    }
    if (state->countdownAnimId != 0) {
      inst->animations.cancel(state->countdownAnimId);
      state->countdownAnimId = 0;
    }

    state->progressBar->setOpacity(1.0f);
    state->progressBar->setProgress(remaining);
    const bool isDriver = (m_instances.size() > 0 && m_instances[0].get() == inst.get());
    state->countdownAnimId = inst->animations.animateUnscaled(
        remaining, 0.0f, static_cast<float>(entry->displayDurationMs) * remaining, Easing::Linear,
        [this, progressBar = state->progressBar, notificationId](float v) {
          progressBar->setProgress(v);
          if (auto* popup = findEntry(notificationId); popup != nullptr) {
            popup->remainingProgress = v;
          }
        },
        [this, notificationId, isDriver]() {
          if (isDriver) {
            DeferredCall::callLater([this, notificationId]() { removePopup(notificationId); });
          }
        },
        state->progressBar);
  }
}

void NotificationToast::revealQueuedEntries() {
  bool placed = false;
  do {
    placed = false;
    for (std::size_t i = 0; i < m_entries.size(); ++i) {
      auto& entry = m_entries[i];
      if (entry.exiting || hasPlacement(entry)) {
        continue;
      }
      const auto placement = findPlacementY(entry.height);
      if (!placement.has_value()) {
        continue;
      }
      entry.y = *placement;
      // Restart the manager-side expiry with the full duration now that the card is
      // actually visible. Matches displayDurationMs so the progress bar and the
      // manager timer finish together.
      if (entry.rawTimeoutMs > 0 && m_notifications != nullptr) {
        m_notifications->resumeExpiry(entry.notificationId, entry.rawTimeoutMs);
      }
      syncEntryVisibility(i);
      placed = true;
    }
  } while (placed);
}

void NotificationToast::evictOverlappingEntries(std::size_t anchorIndex) {
  if (anchorIndex >= m_entries.size() || !hasPlacement(m_entries[anchorIndex])) {
    return;
  }

  const float anchorTop = m_entries[anchorIndex].y;
  const float anchorBottom = anchorTop + m_entries[anchorIndex].height;

  for (std::size_t i = 0; i < m_entries.size(); ++i) {
    if (i == anchorIndex || m_entries[i].exiting || !hasPlacement(m_entries[i])) {
      continue;
    }

    const float entryTop = m_entries[i].y;
    const float entryBottom = entryTop + m_entries[i].height;
    const bool separated = (entryBottom + kGap <= anchorTop + 0.5f) || (anchorBottom + kGap <= entryTop + 0.5f);
    if (separated) {
      continue;
    }

    m_entries[i].y = kQueuedY;
    if (m_entries[i].rawTimeoutMs > 0 && m_notifications != nullptr) {
      m_notifications->pauseExpiry(m_entries[i].notificationId);
    }
    syncEntryVisibility(i);
  }
}

bool NotificationToast::hasPlacement(const PopupEntry& entry) const { return !entry.exiting && entry.y >= 0.0f; }

bool NotificationToast::canKeepPlacement(const PopupEntry& entry, std::optional<uint32_t> ignoreNotificationId) const {
  if (!hasPlacement(entry) || entry.y + entry.height > maxPlacementBottom() + 0.5f) {
    return false;
  }

  const float top = entry.y;
  const float bottom = entry.y + entry.height;
  for (const auto& other : m_entries) {
    if (!hasPlacement(other)) {
      continue;
    }
    if (other.notificationId == entry.notificationId) {
      continue;
    }
    if (ignoreNotificationId.has_value() && other.notificationId == *ignoreNotificationId) {
      continue;
    }

    const float otherTop = other.y;
    const float otherBottom = other.y + other.height;
    const bool separated = (bottom + kGap <= otherTop + 0.5f) || (otherBottom + kGap <= top + 0.5f);
    if (!separated) {
      return false;
    }
  }

  return true;
}

bool NotificationToast::fitsOnSurface(const PopupEntry& entry, float surfaceHeight) const {
  return hasPlacement(entry) && entry.y + entry.height <= layoutBottomForSurfaceHeight(surfaceHeight) + 0.5f;
}

float NotificationToast::entryHeight(const PopupEntry& entry) const {
  if (entry.height > 0.5f) {
    return entry.height;
  }
  return cardHeightForEntry(!entry.actions.empty());
}

std::string NotificationToast::notificationPosition() const {
  if (m_config == nullptr || m_config->config().notification.position.empty()) {
    return "top_right";
  }
  return m_config->config().notification.position;
}

std::vector<std::string> NotificationToast::notificationMonitors() const {
  if (m_config == nullptr) {
    return {};
  }
  return m_config->config().notification.monitors;
}

bool NotificationToast::shouldRenderOnOutput(const WaylandOutput& output) const {
  const auto selectedMonitors = notificationMonitors();
  if (selectedMonitors.empty()) {
    return true;
  }
  return std::any_of(selectedMonitors.begin(), selectedMonitors.end(),
                     [&output](const std::string& match) { return outputMatchesSelector(match, output); });
}

bool NotificationToast::isBottomStacking() const { return isBottomPosition(notificationPosition()); }

bool NotificationToast::revealFromLeftEdge() const { return isLeftPosition(notificationPosition()); }

void NotificationToast::refreshEntryGeometry(PopupEntry& entry) const {
  if (m_renderContext == nullptr) {
    entry.toastSummaryLines = kMaxSummaryLines;
    entry.toastBodyLines = 0;
    entry.height = cardHeightForEntry(!entry.actions.empty());
    return;
  }

  const ToastGeometry planned = planToastLayout(*m_renderContext, entry.summary, entry.body, entry.actions,
                                                cardHeightForEntry(!entry.actions.empty()));
  entry.toastSummaryLines = planned.summaryLines;
  entry.toastBodyLines = planned.bodyLines;
  entry.height = planned.cardHeight;
}

float NotificationToast::layoutBottomForSurfaceHeight(float surfaceHeight) const {
  return std::max(kPaddingTop, surfaceHeight - kPaddingBottom);
}

float NotificationToast::maxPlacementBottom() const {
  float maxSurfaceHeight = 0.0f;
  bool haveSurfaceHeight = false;
  if (m_wayland != nullptr) {
    for (const auto& output : m_wayland->outputs()) {
      if (output.output == nullptr) {
        continue;
      }
      haveSurfaceHeight = true;
      maxSurfaceHeight = std::max(maxSurfaceHeight, static_cast<float>(surfaceHeightForOutput(output.output)));
    }
  }
  for (const auto& inst : m_instances) {
    if (inst != nullptr && inst->surface != nullptr && inst->surface->height() > 0) {
      haveSurfaceHeight = true;
      maxSurfaceHeight = std::max(maxSurfaceHeight, static_cast<float>(inst->surface->height()));
    }
  }
  if (!haveSurfaceHeight) {
    maxSurfaceHeight = static_cast<float>(kFallbackSurfaceHeight);
  }
  return layoutBottomForSurfaceHeight(maxSurfaceHeight);
}

std::optional<float> NotificationToast::findPlacementY(float candidateHeight,
                                                       std::optional<uint32_t> ignoreNotificationId) const {
  struct Interval {
    float top = 0.0f;
    float bottom = 0.0f;
  };

  std::vector<Interval> occupied;
  occupied.reserve(m_entries.size());
  for (const auto& entry : m_entries) {
    if (!hasPlacement(entry)) {
      continue;
    }
    if (ignoreNotificationId.has_value() && entry.notificationId == *ignoreNotificationId) {
      continue;
    }
    occupied.push_back({entry.y, entry.y + entry.height});
  }
  const float bottom = maxPlacementBottom();
  if (isBottomStacking()) {
    std::sort(occupied.begin(), occupied.end(),
              [](const Interval& a, const Interval& b) { return a.bottom > b.bottom; });
    float cursorBottom = bottom;
    for (const auto& interval : occupied) {
      const float candidateTop = cursorBottom - candidateHeight;
      if (candidateTop >= interval.bottom + kGap - 0.5f) {
        return candidateTop;
      }
      cursorBottom = std::min(cursorBottom, interval.top - kGap);
    }
    const float candidateTop = cursorBottom - candidateHeight;
    if (candidateTop >= kPaddingTop - 0.5f) {
      return candidateTop;
    }
    return std::nullopt;
  }

  std::sort(occupied.begin(), occupied.end(), [](const Interval& a, const Interval& b) { return a.top < b.top; });
  float cursor = kPaddingTop;
  for (const auto& interval : occupied) {
    if (cursor + candidateHeight <= interval.top - kGap + 0.5f) {
      return cursor;
    }
    cursor = std::max(cursor, interval.bottom + kGap);
  }

  if (cursor + candidateHeight <= bottom + 0.5f) {
    return cursor;
  }
  return std::nullopt;
}

uint32_t NotificationToast::surfaceHeightForOutput(wl_output* output) const {
  if (m_wayland != nullptr && output != nullptr) {
    if (const auto* wlOutput = m_wayland->findOutputByWl(output); wlOutput != nullptr) {
      const std::int32_t logicalHeight = outputLogicalHeight(*wlOutput);
      if (logicalHeight > 0) {
        const std::int32_t available = logicalHeight - (kSurfaceMargin * 2);
        return static_cast<uint32_t>(std::max(1, available));
      }
    }
  }

  return static_cast<uint32_t>(kFallbackSurfaceHeight);
}

// --- Surface lifecycle ---

void NotificationToast::ensureSurfaces() {
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  const auto surfaceWidth = static_cast<uint32_t>(kSurfaceWidth);
  const std::string position = notificationPosition();
  const auto selectedMonitors = notificationMonitors();
  if (!m_instances.empty() && (position != m_lastPosition || selectedMonitors != m_lastMonitorSelectors)) {
    for (auto& inst : m_instances) {
      inst->animations.cancelAll();
      inst->inputDispatcher.setSceneRoot(nullptr);
    }
    m_instances.clear();
  }
  m_lastPosition = position;
  m_lastMonitorSelectors = selectedMonitors;

  for (const auto& output : m_wayland->outputs()) {
    if (output.output == nullptr) {
      continue;
    }
    if (!shouldRenderOnOutput(output)) {
      continue;
    }
    const auto surfaceHeight = surfaceHeightForOutput(output.output);

    auto existingIt = std::find_if(m_instances.begin(), m_instances.end(), [&output](const auto& inst) {
      return inst != nullptr && inst->output == output.output;
    });
    if (existingIt != m_instances.end()) {
      auto& inst = *existingIt;
      inst->scale = output.scale;
      if (inst->surface != nullptr &&
          (inst->surface->width() != surfaceWidth || inst->surface->height() != surfaceHeight)) {
        inst->surface->requestSize(surfaceWidth, surfaceHeight);
      }
      continue;
    }

    auto inst = std::make_unique<Instance>();
    inst->output = output.output;
    inst->scale = output.scale;

    std::uint32_t anchor = LayerShellAnchor::Top | LayerShellAnchor::Right;
    std::int32_t marginTop = kSurfaceMargin;
    std::int32_t marginRight = kSurfaceMargin;
    std::int32_t marginBottom = kSurfaceMargin;
    std::int32_t marginLeft = kSurfaceMargin;
    if (position == "top_left") {
      anchor = LayerShellAnchor::Top | LayerShellAnchor::Left;
    } else if (position == "top_center") {
      anchor = LayerShellAnchor::Top;
      marginLeft = 0;
      marginRight = 0;
    } else if (position == "bottom_left") {
      anchor = LayerShellAnchor::Bottom | LayerShellAnchor::Left;
    } else if (position == "bottom_center") {
      anchor = LayerShellAnchor::Bottom;
      marginLeft = 0;
      marginRight = 0;
    } else if (position == "bottom_right") {
      anchor = LayerShellAnchor::Bottom | LayerShellAnchor::Right;
    }

    auto surfaceConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-notifications",
        .layer = LayerShellLayer::Top,
        .anchor = anchor,
        .width = surfaceWidth,
        .height = surfaceHeight,
        .exclusiveZone = 0,
        .marginTop = marginTop,
        .marginRight = marginRight,
        .marginBottom = marginBottom,
        .marginLeft = marginLeft,
        .keyboard = LayerShellKeyboard::None,
        .defaultWidth = surfaceWidth,
        .defaultHeight = surfaceHeight,
    };

    inst->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));

    auto* instPtr = inst.get();
    inst->surface->setConfigureCallback(
        [instPtr](uint32_t /*w*/, uint32_t /*h*/) { instPtr->surface->requestLayout(); });
    inst->surface->setPrepareFrameCallback(
        [this, instPtr](bool needsUpdate, bool needsLayout) { prepareFrame(*instPtr, needsUpdate, needsLayout); });
    inst->surface->setFrameTickCallback([this, instPtr](float /*deltaMs*/) {
      // Cards animate horizontally during entry/exit slides; the input and blur regions
      // must follow the visible position or the rounded right edge bleeds.
      if (instPtr->animations.hasActive()) {
        updateInputRegion(*instPtr);
      }
    });
    inst->surface->setAnimationManager(&inst->animations);
    inst->surface->setRenderContext(m_renderContext);

    bool ok = inst->surface->initialize(output.output);
    if (!ok) {
      kLog.warn("notification toast: failed to initialize surface on {}", output.connectorName);
      continue;
    }

    kLog.debug("notification toast: surface created on {}", output.connectorName);
    m_instances.push_back(std::move(inst));
  }
}

void NotificationToast::destroySurfaces() {
  for (auto& inst : m_instances) {
    inst->animations.cancelAll();
    inst->inputDispatcher.setSceneRoot(nullptr);
  }
  m_instances.clear();
  m_entries.clear();
  kLog.debug("notification toast: all surfaces destroyed");
}

void NotificationToast::prepareFrame(Instance& inst, bool /*needsUpdate*/, bool needsLayout) {
  if (m_renderContext == nullptr || inst.surface == nullptr) {
    return;
  }

  const auto width = inst.surface->width();
  const auto height = inst.surface->height();
  if (width == 0 || height == 0) {
    return;
  }

  m_renderContext->makeCurrent(inst.surface->renderTarget());

  const bool needsSceneBuild = inst.sceneRoot == nullptr ||
                               static_cast<uint32_t>(std::round(inst.sceneRoot->width())) != width ||
                               static_cast<uint32_t>(std::round(inst.sceneRoot->height())) != height;
  if (needsSceneBuild || needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(inst, width, height);
  }
}

void NotificationToast::buildScene(Instance& inst, uint32_t width, uint32_t height) {
  uiAssertNotRendering("NotificationToast::buildScene");
  if (m_renderContext == nullptr) {
    return;
  }

  auto w = static_cast<float>(width);
  auto h = static_cast<float>(height);

  auto sceneRoot = std::make_unique<Node>();
  sceneRoot->setSize(w, h);
  sceneRoot->setAnimationManager(&inst.animations);

  inst.inputDispatcher.setSceneRoot(sceneRoot.get());
  inst.sceneRoot = std::move(sceneRoot);
  inst.inputDispatcher.setCursorShapeCallback(
      [this](uint32_t serial, uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

  inst.surface->setSceneRoot(inst.sceneRoot.get());

  // Build cards for any entries that already exist
  inst.cards.clear();
  inst.cards.resize(m_entries.size());
  for (std::size_t i = 0; i < m_entries.size(); ++i) {
    if (!m_entries[i].exiting && hasPlacement(m_entries[i]) &&
        fitsOnSurface(m_entries[i], static_cast<float>(height))) {
      addCardToInstance(inst, i);
    }
  }

  updateInputRegion(inst);
  if (inst.pointerInside) {
    inst.inputDispatcher.pointerMotion(inst.lastPointerX, inst.lastPointerY, 0);
  }
}

void NotificationToast::updateInputRegion(Instance& inst) const {
  if (inst.surface == nullptr) {
    return;
  }

  std::vector<InputRect> rects;
  std::vector<InputRect> blurRects;
  rects.reserve(inst.cards.size());
  for (const auto& card : inst.cards) {
    if (card.cardNode == nullptr) {
      continue;
    }
    if (card.cardNode->width() <= 0.5f || card.cardNode->height() <= 0.5f) {
      continue;
    }
    const int rx = static_cast<int>(std::floor(card.cardNode->x()));
    const int ry = static_cast<int>(std::floor(card.cardNode->y()));
    const int rw = std::max(1, static_cast<int>(std::ceil(card.cardNode->width())));
    const int rh = std::max(1, static_cast<int>(std::ceil(card.cardNode->height())));
    rects.push_back({rx, ry, rw, rh});
    auto strips = Surface::tessellateRoundedRect(rx, ry, rw, rh, Style::radiusXl);
    blurRects.insert(blurRects.end(), strips.begin(), strips.end());
  }

  inst.surface->setInputRegion(rects);
  inst.surface->setBlurRegion(blurRects);
}

float NotificationToast::cardReveal(const Instance::CardState& cs) const { return cardRevealFromNode(cs.cardNode); }

void NotificationToast::applyCardReveal(Instance::CardState& cs, float reveal, float y) const {
  applyCardRevealNodes(cs.cardNode, cs.cardContent, cs.cardForeground, reveal, y, revealFromLeftEdge());
}

InputArea* NotificationToast::buildCard(const PopupEntry& entry, Node** outCardContent, Node** outCardForeground,
                                        Label** outAppName, Label** outSummary, Label** outBody, Node** outBg,
                                        Node** outAppIcon, ProgressBar** outProgress, Glyph** outCloseGlyph) {
  const float cardHeight = entry.height > 0.5f ? entry.height : cardHeightForEntry(!entry.actions.empty());
  const float innerWidth = kCardWidth - kCardInnerPad * 2;
  const float progressY = cardHeight - kProgressHeight - kProgressBottomMargin;

  auto viewport = std::make_unique<InputArea>();
  viewport->setSize(kCardWidth, cardHeight);
  viewport->setClipChildren(true);
  // Unified close mechanism: clicking anywhere on the card dismisses it. The (X) glyph
  // is purely visual — it brightens while the card is hovered via the card's own
  // onEnter/onLeave handlers installed in addCardToInstance().
  viewport->setOnClick([this, id = entry.notificationId](const InputArea::PointerData& data) {
    if (data.button == BTN_LEFT) {
      removePopup(id);
    }
  });

  auto cardRoot = std::make_unique<Node>();
  cardRoot->setSize(kCardWidth, cardHeight);
  *outCardContent = cardRoot.get();

  auto foreground = std::make_unique<Node>();
  foreground->setSize(kCardWidth, cardHeight);
  *outCardForeground = foreground.get();

  const bool isCritical = (entry.urgency == Urgency::Critical);
  const float textStartX = notificationTextStartX();
  const float textMaxWidth = notificationTextMaxWidth();
  const float bgAlpha = m_config != nullptr ? m_config->config().notification.backgroundOpacity : 0.97f;

  // Background
  auto bg = std::make_unique<Box>();
  bg->setCardStyle();
  bg->setRadius(Style::radiusXl);
  if (isCritical) {
    // Keep critical toasts readable: surface background + urgent border.
    bg->setFill(roleColor(ColorRole::Surface, bgAlpha));
    bg->setBorder(roleColor(ColorRole::Error, 0.95f), Style::borderWidth * 1.4f);
  } else {
    bg->setFill(roleColor(ColorRole::Surface, bgAlpha));
    bg->setBorder(roleColor(ColorRole::Outline, 0.8f), Style::borderWidth);
  }
  bg->setSize(kCardWidth, cardHeight);
  *outBg = cardRoot->addChild(std::move(bg));

  // Header row: app name (left) + close glyph (right), vertically centred via Flex
  auto headerRow = std::make_unique<Flex>();
  headerRow->setDirection(FlexDirection::Horizontal);
  headerRow->setJustify(FlexJustify::SpaceBetween);
  headerRow->setAlign(FlexAlign::Center);
  headerRow->setSize(innerWidth, kCloseButtonSize);
  headerRow->setPosition(kCardInnerPad, kCardInnerPad);

  auto headerLeft = std::make_unique<Flex>();
  headerLeft->setDirection(FlexDirection::Horizontal);
  headerLeft->setAlign(FlexAlign::Center);
  headerLeft->setGap(Style::spaceXs);

  auto iconSlot = std::make_unique<Node>();
  iconSlot->setSize(kNotificationIconSize, kNotificationIconSize);
  iconSlot->setPosition(kCardInnerPad, std::round((cardHeight - kNotificationIconSize) * 0.5f));

  bool iconAssigned = false;
  const std::string iconPath = resolveNotificationIconPath(entry);
  if (!iconPath.empty()) {
    auto appIcon = std::make_unique<Image>();
    appIcon->setSize(kNotificationIconSize, kNotificationIconSize);
    appIcon->setPosition(0.0f, 0.0f);
    appIcon->setRadius(kNotificationIconRadius);
    appIcon->setFit(ImageFit::Cover);
    if (appIcon->setSourceFile(*m_renderContext, iconPath, static_cast<int>(std::round(kNotificationIconSize)))) {
      *outAppIcon = iconSlot->addChild(std::move(appIcon));
      iconAssigned = true;
    } else {
      kLog.warn("notification toast: failed to load icon image for #{} from '{}'", entry.notificationId, iconPath);
    }
  } else if (entry.imageData.has_value()) {
    const auto& image = *entry.imageData;
    if (image.width > 0 && image.height > 0 && !image.data.empty()) {
      auto appIcon = std::make_unique<Image>();
      appIcon->setSize(kNotificationIconSize, kNotificationIconSize);
      appIcon->setPosition(0.0f, 0.0f);
      appIcon->setRadius(kNotificationIconRadius);
      appIcon->setFit(ImageFit::Cover);
      const bool validImageMetadata = image.bitsPerSample == 8 && ((image.channels == 4 && image.hasAlpha) ||
                                                                   (image.channels == 3 && !image.hasAlpha));
      const PixmapFormat format = image.channels == 3 ? PixmapFormat::RGB : PixmapFormat::RGBA;
      if (validImageMetadata && appIcon->setSourceRaw(*m_renderContext, image.data.data(), image.data.size(),
                                                      image.width, image.height, image.rowStride, format, true)) {
        *outAppIcon = iconSlot->addChild(std::move(appIcon));
        iconAssigned = true;
      } else if (!validImageMetadata) {
        kLog.warn("notification toast: unsupported image-data avatar metadata for #{} (alpha={}, bits={}, channels={})",
                  entry.notificationId, image.hasAlpha, image.bitsPerSample, image.channels);
      } else {
        kLog.warn("notification toast: failed to load image-data avatar for #{} ({}x{}, bytes={})",
                  entry.notificationId, image.width, image.height, image.data.size());
      }
    } else {
      kLog.warn("notification toast: invalid image-data avatar for #{} ({}x{}, bytes={})", entry.notificationId,
                image.width, image.height, image.data.size());
    }
  }

  if (!iconAssigned) {
    auto fallback = std::make_unique<Glyph>();
    fallback->setGlyph("bell");
    fallback->setGlyphSize(kNotificationIconGlyphSize);
    fallback->setColor(roleColor(ColorRole::OnSurfaceVariant));
    fallback->measure(*m_renderContext);
    fallback->setPosition(std::round((kNotificationIconSize - fallback->width()) * 0.5f),
                          std::round((kNotificationIconSize - fallback->height()) * 0.5f));
    *outAppIcon = iconSlot->addChild(std::move(fallback));
  }

  foreground->addChild(std::move(iconSlot));

  auto appName = std::make_unique<Label>();
  appName->setText(entry.appName);
  appName->setFontSize(kMetaFontSize);
  appName->setColor(roleColor(isCritical ? ColorRole::Error : ColorRole::OnSurfaceVariant));
  appName->setMaxWidth(innerWidth - kCloseButtonSize - Style::spaceXs);
  appName->measure(*m_renderContext);
  *outAppName = appName.get();
  headerLeft->addChild(std::move(appName));
  headerLeft->layout(*m_renderContext);
  headerRow->addChild(std::move(headerLeft));

  auto closeGlyph = std::make_unique<Glyph>();
  closeGlyph->setGlyph("close");
  closeGlyph->setGlyphSize(kCloseGlyphSize);
  closeGlyph->setColor(resolveThemeColor(isCritical ? roleColor(ColorRole::Error, 0.75f)
                                                    : roleColor(ColorRole::OnSurfaceVariant, 0.6f)));
  *outCloseGlyph = static_cast<Glyph*>(headerRow->addChild(std::move(closeGlyph)));
  headerRow->layout(*m_renderContext);

  foreground->addChild(std::move(headerRow));

  // Summary (bold title) — Pango handles wrap + ellipsize.
  auto summary = std::make_unique<Label>();
  summary->setText(entry.summary);
  summary->setFontSize(kSummaryFontSize);
  summary->setColor(roleColor(ColorRole::OnSurface));
  summary->setBold(true);
  summary->setMaxWidth(textMaxWidth);
  std::unique_ptr<Flex> actionsRow;
  float actionsReservedHeight = 0.0f;
  if (!entry.actions.empty()) {
    actionsRow = std::make_unique<Flex>();
    actionsRow->setDirection(FlexDirection::Horizontal);
    actionsRow->setAlign(FlexAlign::Center);
    actionsRow->setGap(kActionGap);

    const uint32_t notificationId = entry.notificationId;
    const int totalDuration = entry.displayDurationMs;
    int actionCount = 0;
    for (std::size_t i = 0; i + 1 < entry.actions.size() && actionCount < kMaxActionButtons; i += 2) {
      const std::string actionKey = entry.actions[i];
      std::string actionLabel = entry.actions[i + 1];
      if (isBlankText(actionLabel)) {
        actionLabel = fallbackActionLabel();
      }
      if (actionKey.empty()) {
        continue;
      }

      auto actionButton = std::make_unique<Button>();
      actionButton->setVariant(ButtonVariant::Outline);
      actionButton->setFontSize(Style::fontSizeCaption);
      actionButton->setText(actionLabel);
      actionButton->setOnEnter([this, notificationId]() {
        pauseCountdowns(notificationId);
        if (m_notifications != nullptr) {
          m_notifications->pauseExpiry(notificationId);
        }
      });
      actionButton->setOnLeave([this, notificationId, totalDuration]() {
        if (totalDuration < 0) {
          return;
        }
        const auto* popup = findEntry(notificationId);
        if (popup == nullptr) {
          return;
        }
        const float remaining = std::clamp(popup->remainingProgress, 0.0f, 1.0f);
        if (remaining <= 0.0f) {
          if (m_notifications != nullptr) {
            m_notifications->resumeExpiry(notificationId, 0);
          }
          return;
        }
        const int32_t remainingMs =
            std::max<int32_t>(1, static_cast<int32_t>(std::ceil(static_cast<float>(totalDuration) * remaining)));
        if (m_notifications != nullptr) {
          m_notifications->resumeExpiry(notificationId, remainingMs);
        }
        resumeCountdowns(notificationId);
      });
      actionButton->setOnClick([this, id = entry.notificationId, actionKey]() {
        if (m_notifications == nullptr) {
          return;
        }
        if (!m_notifications->invokeAction(id, actionKey, true)) {
          kLog.warn("notification toast: failed to invoke action '{}' for #{}", actionKey, id);
        }
      });
      actionsRow->addChild(std::move(actionButton));
      ++actionCount;
    }

    if (actionCount > 0) {
      actionsRow->layout(*m_renderContext);
      actionsReservedHeight = actionsRow->height() + kActionRowGap;
      actionsRow->setPosition(textStartX, progressY - actionsRow->height() - kActionRowGap);
    } else {
      actionsRow.reset();
    }
  }

  summary->setMaxLines(std::max(1, entry.toastSummaryLines));
  summary->measure(*m_renderContext);
  summary->setPosition(textStartX, kCardInnerPad + kCloseButtonSize + kMetaGap);
  const float summaryMeasuredH = summary->height();
  *outSummary = summary.get();
  foreground->addChild(std::move(summary));

  auto body = std::make_unique<Label>();
  body->setText(entry.body);
  body->setFontSize(kBodyFontSize);
  body->setColor(roleColor(ColorRole::OnSurfaceVariant));
  body->setMaxWidth(textMaxWidth);
  const float bodyHeight = availableBodyHeight(summaryMeasuredH, actionsReservedHeight, cardHeight);
  const int bodyLines = entry.toastBodyLines;
  body->setMaxLines(std::max(1, bodyLines));
  if (bodyLines <= 0) {
    body->setText("");
    body->setVisible(false);
  }
  body->measure(*m_renderContext);
  body->setPosition(textStartX, bodyTopForSummary(summaryMeasuredH));
  clampBodyLabelHeight(*body, bodyHeight);
  *outBody = body.get();
  foreground->addChild(std::move(body));

  if (actionsRow != nullptr) {
    foreground->addChild(std::move(actionsRow));
  }

  // Progress bar (countdown)
  auto progressBar = std::make_unique<ProgressBar>();
  progressBar->setTrackColor(roleColor(ColorRole::OnSurfaceVariant, 0.35f));
  progressBar->setFillColor(roleColor(isCritical ? ColorRole::Error : ColorRole::Primary));
  progressBar->setSize(innerWidth, kProgressHeight);
  progressBar->setPosition(kCardInnerPad, progressY);
  *outProgress = static_cast<ProgressBar*>(foreground->addChild(std::move(progressBar)));

  cardRoot->addChild(std::move(foreground));
  viewport->addChild(std::move(cardRoot));

  return viewport.release();
}

// --- Pointer events ---

bool NotificationToast::onPointerEvent(const PointerEvent& event) {
  bool consumed = false;

  for (auto& inst : m_instances) {
    switch (event.type) {
    case PointerEvent::Type::Enter:
      if (event.surface == inst->surface->wlSurface()) {
        inst->pointerInside = true;
        inst->lastPointerX = static_cast<float>(event.sx);
        inst->lastPointerY = static_cast<float>(event.sy);
        inst->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
      }
      break;
    case PointerEvent::Type::Leave:
      if (event.surface == inst->surface->wlSurface()) {
        inst->pointerInside = false;
        inst->inputDispatcher.pointerLeave();
      }
      break;
    case PointerEvent::Type::Motion:
      if (inst->pointerInside) {
        inst->lastPointerX = static_cast<float>(event.sx);
        inst->lastPointerY = static_cast<float>(event.sy);
        inst->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
      }
      break;
    case PointerEvent::Type::Button:
      if (inst->pointerInside) {
        inst->lastPointerX = static_cast<float>(event.sx);
        inst->lastPointerY = static_cast<float>(event.sy);
        bool pressed = (event.state == 1);
        inst->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                            pressed);
        consumed = true;
      }
      break;
    case PointerEvent::Type::Axis:
      break;
    }

    // Hover state changes on child controls (buttons, close icons) can mark the tree
    // layoutDirty, but toast cards do not actually change geometry on hover — and
    // requestLayout() here would tear down the whole scene via buildScene(), killing
    // any in-flight entry/exit/slide/countdown animations. Treat pointer-driven dirt
    // as a redraw.
    if (inst->sceneRoot != nullptr && (inst->sceneRoot->paintDirty() || inst->sceneRoot->layoutDirty())) {
      inst->surface->requestRedraw();
    }
  }

  return consumed;
}

std::string NotificationToast::resolveNotificationIconPath(const PopupEntry& entry) {
  if (!entry.icon.has_value() || entry.icon->empty()) {
    return {};
  }

  const std::string iconValue = *entry.icon;

  if (isRemoteIconUrl(iconValue)) {
    if (const auto it = m_remoteIconCache.find(iconValue); it != m_remoteIconCache.end()) {
      std::error_code ec;
      if (std::filesystem::exists(it->second, ec) && std::filesystem::file_size(it->second, ec) > 0) {
        return it->second;
      }
      kLog.warn("notification toast: #{} remote cache entry stale path='{}'", entry.notificationId, it->second);
      m_remoteIconCache.erase(it);
    }

    if (m_failedRemoteIconDownloads.find(iconValue) != m_failedRemoteIconDownloads.end()) {
      kLog.warn("notification toast: #{} remote icon URL marked failed url='{}'", entry.notificationId, iconValue);
      return {};
    }

    const auto cached = remoteIconCachePath(iconValue);
    std::error_code ec;
    if (std::filesystem::exists(cached, ec) && std::filesystem::file_size(cached, ec) > 0) {
      const std::string cachedPath = cached.string();
      m_remoteIconCache[iconValue] = cachedPath;
      return cachedPath;
    }

    if (m_httpClient != nullptr && m_pendingRemoteIconDownloads.find(iconValue) == m_pendingRemoteIconDownloads.end()) {
      std::filesystem::create_directories(cached.parent_path(), ec);
      if (ec) {
        kLog.warn("notification toast: #{} failed to create icon cache dir '{}' error='{}'", entry.notificationId,
                  cached.parent_path().string(), ec.message());
      }

      m_pendingRemoteIconDownloads.insert(iconValue);
      m_httpClient->download(iconValue, cached, [this, url = iconValue, path = cached.string()](bool success) {
        m_pendingRemoteIconDownloads.erase(url);
        if (!success) {
          kLog.warn("notification toast: remote icon download failed url='{}'", url);
          m_failedRemoteIconDownloads.insert(url);
          return;
        }

        m_failedRemoteIconDownloads.erase(url);
        m_remoteIconCache[url] = path;
        for (auto& inst : m_instances) {
          if (inst->surface != nullptr) {
            inst->surface->requestLayout();
          }
        }
      });
    } else if (m_httpClient == nullptr) {
      kLog.warn("notification toast: cannot download remote icon url='{}' because HttpClient is null", iconValue);
    }
    return {};
  }

  const std::string localPath = normalizeLocalIconPath(iconValue);
  if (!localPath.empty() && localPath.front() == '/') {
    if (access(localPath.c_str(), R_OK) == 0) {
      return localPath;
    }
    kLog.warn("notification toast: #{} local icon path not readable path='{}'", entry.notificationId, localPath);
    return {};
  }

  if (localPath.empty()) {
    kLog.warn("notification toast: #{} icon value normalized to empty path", entry.notificationId);
    return {};
  }

  const std::string& resolved = m_iconResolver.resolve(localPath);
  if (!resolved.empty()) {
    return resolved;
  }

  kLog.warn("notification toast: #{} theme icon not found name='{}'", entry.notificationId, localPath);
  return {};
}
