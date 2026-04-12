#include "shell/notification/notification_toast.h"

#include "notification/notification_manager.h"
#include "config/config_service.h"
#include "core/deferred_call.h"
#include "core/log.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "ui/controls/box.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/label.h"
#include "ui/controls/progress_bar.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <cmath>
#include <linux/input-event-codes.h>

namespace {

constexpr Logger kLog("notification");

constexpr int kCardWidth = 340;
constexpr int kCardMinHeight = 78;
constexpr int kCardMaxHeight = 130;

constexpr std::size_t kMaxVisible = 5;
constexpr float kGap = Style::spaceSm;
constexpr float kPadding = Style::spaceMd;
constexpr float kCardInnerPad = Style::spaceMd;
constexpr float kCloseButtonSize = 20.0f;
constexpr float kCloseGlyphSize = 12.0f;

// Maps the raw DBus timeout value to a popup display duration.
// Returns -1 to mean "persistent — never auto-dismiss".
int resolveDisplayDuration(int32_t timeout) {
  if (timeout == 0)  return -1;
  if (timeout == -1) return kDefaultNotificationTimeout;
  return std::max(1000, static_cast<int>(timeout));
}
constexpr int kProgressHeight = 3;
constexpr int kSlideOffset = 20;                            // horizontal slide distance for entry/exit animation
constexpr float kProgressBottomMargin = Style::spaceMd;    // space below progress bar to card edge
constexpr float kProgressTopGap = Style::spaceSm;          // gap from text content to progress bar

constexpr float kMetaFontSize = Style::fontSizeCaption;
constexpr float kSummaryFontSize = Style::fontSizeTitle;
constexpr float kBodyFontSize = Style::fontSizeBody;

constexpr float kMetaGap = Style::spaceXs;        // vertical gap between app name and summary
constexpr float kSummaryBodyGap = Style::spaceXs; // vertical gap between summary and body

constexpr std::size_t kMaxSummaryLines = 2;
constexpr std::size_t kMaxBodyLines = 3;

constexpr int kSurfaceWidth = static_cast<int>(kCardWidth + kPadding * 2);
constexpr int kSurfaceHeight = static_cast<int>(kCardMaxHeight * kMaxVisible + kGap * (kMaxVisible - 1) + kPadding * 2);

} // namespace

NotificationToast::NotificationToast() = default;

NotificationToast::~NotificationToast() {
  if (m_notifications != nullptr && m_callbackToken >= 0) {
    m_notifications->removeEventCallback(m_callbackToken);
  }
}

void NotificationToast::initialize(WaylandConnection& wayland, ConfigService* config,
                                   NotificationManager* notifications, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_notifications = notifications;
  m_renderContext = renderContext;

  m_callbackToken = m_notifications->addEventCallback(
      [this](const Notification& n, NotificationEvent event) { onNotificationEvent(n, event); });
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
    addPopup(n);
    break;
  case NotificationEvent::Updated: {
    for (std::size_t i = 0; i < m_entries.size(); ++i) {
      if (m_entries[i].notificationId == n.id && !m_entries[i].exiting) {
        m_entries[i].appName = n.appName;
        m_entries[i].summary = n.summary;
        m_entries[i].body = n.body;
        updateEntryLayout(m_entries[i]);

        // Update text nodes and reset countdown on each instance
        for (auto& inst : m_instances) {
          if (i >= inst->cards.size()) {
            continue;
          }
          auto& cs = inst->cards[i];
          if (cs.cardNode == nullptr) {
            continue;
          }

          const float newHeight = m_entries[i].cardHeight;
          cs.cardNode->setSize(kCardWidth, newHeight);
          cs.cardBg->setSize(kCardWidth, newHeight); // Surface::setSize auto-syncs internal rect

          cs.appNameLabel->setText(n.appName);
          cs.summaryLabel->setText(m_entries[i].summary);
          cs.summaryLabel->measure(*m_renderContext);
          cs.bodyLabel->setText(m_entries[i].body);
          cs.bodyLabel->measure(*m_renderContext);
          cs.bodyLabel->setPosition(kCardInnerPad, kCardInnerPad + kCloseButtonSize + kMetaGap +
                                                       m_entries[i].summaryHeight + kSummaryBodyGap);

          const float progressY = newHeight - kProgressHeight - kProgressBottomMargin;
          cs.progressBar->setPosition(kCardInnerPad, progressY);

          // Reset countdown
          if (cs.countdownAnimId != 0) {
            inst->animations.cancel(cs.countdownAnimId);
          }
          const int newDuration = resolveDisplayDuration(n.timeout);
          m_entries[i].displayDurationMs = newDuration;
          if (newDuration < 0) {
            cs.progressBar->setOpacity(0.0f);
            cs.countdownAnimId = 0;
          } else {
            cs.progressBar->setOpacity(1.0f);
            cs.progressBar->setProgress(1.0f);
            cs.countdownAnimId = inst->animations.animate(
                1.0f, 0.0f, static_cast<float>(newDuration), Easing::Linear, [pb = cs.progressBar](float v) { pb->setProgress(v); },
                [this, id = n.id]() { DeferredCall::callLater([this, id]() { removePopup(id); }); });
          }

          // Flash
          cs.cardNode->setOpacity(0.7f);
          inst->animations.animate(0.7f, 1.0f, Style::animFast, Easing::EaseOutCubic,
                                   [card = cs.cardNode](float v) { card->setOpacity(v); });

          inst->surface->requestRedraw();
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

  std::size_t visibleCount =
      std::count_if(m_entries.begin(), m_entries.end(), [](const PopupEntry& entry) { return !entry.exiting; });
  while (visibleCount >= kMaxVisible) {
    const auto it =
        std::find_if(m_entries.begin(), m_entries.end(), [](const PopupEntry& entry) { return !entry.exiting; });
    if (it == m_entries.end()) {
      break;
    }

    dismissPopup(static_cast<std::size_t>(std::distance(m_entries.begin(), it)));
    --visibleCount;
  }

  ensureSurfaces();

  PopupEntry entry;
  entry.notificationId = n.id;
  entry.appName = n.appName;
  entry.summary = n.summary;
  entry.body = n.body;
  entry.urgency = n.urgency;
  entry.displayDurationMs = resolveDisplayDuration(n.timeout);
  updateEntryLayout(entry);
  m_entries.push_back(std::move(entry));
  std::size_t index = m_entries.size() - 1;

  for (auto& inst : m_instances) {
    if (inst->sceneRoot == nullptr) {
      continue;
    }
    addCardToInstance(*inst, index);
  }

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

  for (auto& inst : m_instances) {
    dismissCardFromInstance(*inst, index);
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
      auto& cs = inst->cards[index];
      if (cs.countdownAnimId != 0) {
        inst->animations.cancel(cs.countdownAnimId);
        cs.countdownAnimId = 0;
      }
      if (cs.entryAnimId != 0) {
        inst->animations.cancel(cs.entryAnimId);
        cs.entryAnimId = 0;
      }
      if (cs.slideAnimId != 0) {
        inst->animations.cancel(cs.slideAnimId);
        cs.slideAnimId = 0;
      }
      if (cs.exitAnimId != 0) {
        inst->animations.cancel(cs.exitAnimId);
        cs.exitAnimId = 0;
      }

      Node* card = cs.cardNode;
      if (inst->sceneRoot != nullptr && card != nullptr) {
        inst->sceneRoot->removeChild(card);
      }
      inst->cards.erase(inst->cards.begin() + static_cast<std::ptrdiff_t>(index));
    }
  }

  m_entries.erase(m_entries.begin() + static_cast<std::ptrdiff_t>(index));

  if (m_entries.empty()) {
    destroySurfaces();
  } else {
    for (auto& inst : m_instances) {
      layoutCards(*inst);
    }
  }
}

// --- Per-instance card management ---

void NotificationToast::addCardToInstance(PopupInstance& inst, std::size_t entryIndex) {
  auto& entry = m_entries[entryIndex];

  PopupInstance::CardState cs;
  Node* card = buildCard(entry, &cs.appNameLabel, &cs.summaryLabel, &cs.bodyLabel, &cs.cardBg, &cs.progressBar);
  cs.cardNode = card;

  float targetY = cardTargetY(entryIndex);
  card->setPosition(kPadding + kSlideOffset, targetY);
  card->setOpacity(0.0f);

  inst.sceneRoot->addChild(std::unique_ptr<Node>(card));

  // Entry animation
  cs.entryAnimId = inst.animations.animate(
      0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic,
      [card, targetY](float v) {
        card->setOpacity(v);
        card->setPosition(kPadding + kSlideOffset * (1.0f - v), targetY);
      },
      [&inst, entryIndex]() {
        if (entryIndex < inst.cards.size()) {
          inst.cards[entryIndex].entryAnimId = 0;
        }
      });

  // Countdown (only the first instance drives the timeout to avoid duplicate removals)
  bool isDriver = (m_instances.size() > 0 && m_instances[0].get() == &inst);
  if (entry.displayDurationMs < 0) {
    // Persistent — no countdown, no auto-dismiss
    cs.progressBar->setOpacity(0.0f);
    cs.countdownAnimId = 0;
  } else {
    cs.countdownAnimId = inst.animations.animate(
        1.0f, 0.0f, static_cast<float>(entry.displayDurationMs), Easing::Linear, [pb = cs.progressBar](float v) { pb->setProgress(v); },
        [this, id = entry.notificationId, isDriver]() {
          if (isDriver) {
            DeferredCall::callLater([this, id]() { removePopup(id); });
          }
        });
  }

  inst.cards.push_back(cs);
  updateInputRegion(inst);
  inst.surface->requestRedraw();
}

void NotificationToast::dismissCardFromInstance(PopupInstance& inst, std::size_t entryIndex) {
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

  Node* card = cs.cardNode;
  float startX = card->x();
  const uint32_t removingId = (entryIndex < m_entries.size()) ? m_entries[entryIndex].notificationId : 0;

  // Only the first instance drives finishRemoval
  bool isDriver = (m_instances.size() > 0 && m_instances[0].get() == &inst);
  cs.exitAnimId = inst.animations.animate(
      1.0f, 0.0f, Style::animNormal, Easing::EaseInOutQuad,
      [card, startX](float v) {
        card->setOpacity(v);
        card->setPosition(startX + kSlideOffset * (1.0f - v), card->y());
      },
      [this, &inst, entryIndex, isDriver, removingId]() {
        if (entryIndex < inst.cards.size()) {
          inst.cards[entryIndex].exitAnimId = 0;
        }
        if (isDriver && removingId != 0) {
          DeferredCall::callLater([this, removingId]() { finishRemoval(removingId); });
        }
      });

  updateInputRegion(inst);
  inst.surface->requestRedraw();
}

void NotificationToast::layoutCards(PopupInstance& inst) {
  for (std::size_t i = 0; i < inst.cards.size(); ++i) {
    auto& cs = inst.cards[i];
    if (i < m_entries.size() && m_entries[i].exiting) {
      continue;
    }
    if (cs.cardNode == nullptr) {
      continue;
    }

    float targetY = cardTargetY(i);
    float currentY = cs.cardNode->y();
    if (std::abs(currentY - targetY) < 0.5f) {
      continue;
    }

    if (cs.slideAnimId != 0) {
      inst.animations.cancel(cs.slideAnimId);
    }

    Node* card = cs.cardNode;
    cs.slideAnimId = inst.animations.animate(
        currentY, targetY, Style::animNormal, Easing::EaseOutCubic,
        [card](float y) { card->setPosition(card->x(), y); },
        [&inst, i]() {
          if (i < inst.cards.size()) {
            inst.cards[i].slideAnimId = 0;
          }
        });
  }

  updateInputRegion(inst);
  inst.surface->requestRedraw();
}

float NotificationToast::cardTargetY(std::size_t index) const {
  float y = kPadding;
  for (std::size_t i = 0; i < index && i < m_entries.size(); ++i) {
    y += m_entries[i].cardHeight + kGap;
  }
  return y;
}

void NotificationToast::updateEntryLayout(PopupEntry& entry) const {
  const float textWidth = kCardWidth - kCardInnerPad * 2;

  // Let Pango do the wrapping/ellipsizing. We just need the measured pixel
  // height of each block so we can stack them and size the card.
  entry.summaryHeight = 0.0f;
  entry.bodyHeight = 0.0f;
  if (m_renderContext != nullptr) {
    if (!entry.summary.empty()) {
      const auto sm = m_renderContext->measureText(entry.summary, kSummaryFontSize, /*bold=*/true, textWidth,
                                                   kMaxSummaryLines);
      entry.summaryHeight = sm.bottom - sm.top;
    }
    if (!entry.body.empty()) {
      const auto bm =
          m_renderContext->measureText(entry.body, kBodyFontSize, /*bold=*/false, textWidth, kMaxBodyLines);
      entry.bodyHeight = bm.bottom - bm.top;
    }
  }

  const float contentHeight = kCardInnerPad + kCloseButtonSize + kMetaGap + entry.summaryHeight + kSummaryBodyGap +
                              entry.bodyHeight;
  entry.cardHeight = std::max(static_cast<float>(kCardMinHeight),
                              contentHeight + kProgressTopGap + kProgressHeight + kProgressBottomMargin);
}

// --- Surface lifecycle ---

void NotificationToast::ensureSurfaces() {
  if (!m_instances.empty()) {
    return;
  }
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  std::uint32_t barHeight = Style::barHeightDefault;
  if (m_config != nullptr && !m_config->config().bars.empty()) {
    barHeight = m_config->config().bars[0].height;
  }

  auto surfaceWidth = static_cast<uint32_t>(kSurfaceWidth);
  auto surfaceHeight = static_cast<uint32_t>(kSurfaceHeight);

  for (const auto& output : m_wayland->outputs()) {
    auto inst = std::make_unique<PopupInstance>();
    inst->output = output.output;
    inst->scale = output.scale;

    auto surfaceConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-notifications",
        .layer = LayerShellLayer::Top,
        .anchor = LayerShellAnchor::Top | LayerShellAnchor::Right,
        .width = surfaceWidth,
        .height = surfaceHeight,
        .exclusiveZone = 0,
        .marginTop = static_cast<std::int32_t>(barHeight) + 4,
        .marginRight = 8,
        .keyboard = LayerShellKeyboard::None,
        .defaultWidth = surfaceWidth,
        .defaultHeight = surfaceHeight,
    };

    inst->surface = std::make_unique<LayerSurface>(*m_wayland, std::move(surfaceConfig));

    auto* instPtr = inst.get();
    inst->surface->setConfigureCallback([this, instPtr](uint32_t w, uint32_t h) { buildScene(*instPtr, w, h); });
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

void NotificationToast::buildScene(PopupInstance& inst, uint32_t width, uint32_t height) {
  if (m_renderContext == nullptr) {
    return;
  }

  auto w = static_cast<float>(width);
  auto h = static_cast<float>(height);

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);

  inst.inputDispatcher.setSceneRoot(inst.sceneRoot.get());
  inst.inputDispatcher.setCursorShapeCallback(
      [this](uint32_t serial, uint32_t shape) { m_wayland->setCursorShape(serial, shape); });

  inst.surface->setSceneRoot(inst.sceneRoot.get());

  // Build cards for any entries that already exist
  inst.cards.clear();
  for (std::size_t i = 0; i < m_entries.size(); ++i) {
    if (!m_entries[i].exiting) {
      addCardToInstance(inst, i);
    }
  }

  updateInputRegion(inst);
}

void NotificationToast::updateInputRegion(PopupInstance& inst) const {
  if (inst.surface == nullptr) {
    return;
  }

  std::vector<InputRect> rects;
  rects.reserve(inst.cards.size());
  for (const auto& card : inst.cards) {
    if (card.cardNode == nullptr) {
      continue;
    }
    rects.push_back({
        .x = static_cast<int>(std::floor(card.cardNode->x())),
        .y = static_cast<int>(std::floor(card.cardNode->y())),
        .width = std::max(1, static_cast<int>(std::ceil(card.cardNode->width()))),
        .height = std::max(1, static_cast<int>(std::ceil(card.cardNode->height()))),
    });
  }

  inst.surface->setInputRegion(rects);
}

Node* NotificationToast::buildCard(const PopupEntry& entry, Label** outAppName, Label** outSummary, Label** outBody,
                                   Node** outBg, ProgressBar** outProgress) {
  const float innerWidth = kCardWidth - kCardInnerPad * 2;
  const float progressY = entry.cardHeight - kProgressHeight - kProgressBottomMargin;

  auto area = std::make_unique<InputArea>();
  area->setSize(kCardWidth, entry.cardHeight);
  area->setOnClick([this, id = entry.notificationId](const InputArea::PointerData& data) {
    if (data.button == BTN_LEFT) {
      removePopup(id);
    }
  });

  const bool isCritical = (entry.urgency == Urgency::Critical);

  // Background
  auto bg = std::make_unique<Box>();
  bg->setCardStyle();
  if (isCritical) {
    bg->setFill(roleColor(ColorRole::Error));
  }
  bg->setSize(kCardWidth, entry.cardHeight);
  *outBg = area->addChild(std::move(bg));

  const Color closeColorNormal = resolveThemeColor(
      isCritical ? roleColor(ColorRole::OnError, 0.6f) : roleColor(ColorRole::OnSurfaceVariant, 0.6f));
  const Color closeColorHover =
      resolveThemeColor(isCritical ? roleColor(ColorRole::OnError) : roleColor(ColorRole::OnSurface));

  // Header row: app name (left) + close button (right), vertically centred via Flex
  auto headerRow = std::make_unique<Flex>();
  headerRow->setDirection(FlexDirection::Horizontal);
  headerRow->setJustify(FlexJustify::SpaceBetween);
  headerRow->setAlign(FlexAlign::Center);
  headerRow->setSize(innerWidth, kCloseButtonSize);
  headerRow->setPosition(kCardInnerPad, kCardInnerPad);

  auto appName = std::make_unique<Label>();
  appName->setText(entry.appName);
  appName->setFontSize(kMetaFontSize);
  appName->setColor(roleColor(isCritical ? ColorRole::OnError : ColorRole::OnSurfaceVariant));
  appName->measure(*m_renderContext);
  *outAppName = appName.get();
  headerRow->addChild(std::move(appName));

  auto closeArea = std::make_unique<InputArea>();
  closeArea->setSize(kCloseButtonSize, kCloseButtonSize);
  closeArea->setOnClick([this, id = entry.notificationId](const InputArea::PointerData& data) {
    if (data.button == BTN_LEFT) {
      removePopup(id);
    }
  });
  auto closeGlyph = std::make_unique<Glyph>();
  closeGlyph->setGlyph("close");
  closeGlyph->setGlyphSize(kCloseGlyphSize);
  closeGlyph->setColor(closeColorNormal);
  closeGlyph->setPosition((kCloseButtonSize - kCloseGlyphSize) * 0.5f, (kCloseButtonSize - kCloseGlyphSize) * 0.5f);
  auto* closeGlyphPtr = static_cast<Glyph*>(closeArea->addChild(std::move(closeGlyph)));
  closeArea->setOnEnter([closeGlyphPtr, closeColorHover](const InputArea::PointerData&) {
    closeGlyphPtr->setColor(closeColorHover);
  });
  closeArea->setOnLeave([closeGlyphPtr, closeColorNormal]() {
    closeGlyphPtr->setColor(closeColorNormal);
  });
  headerRow->addChild(std::move(closeArea));

  area->addChild(std::move(headerRow));

  // Summary (bold title) — Pango handles wrap + ellipsize.
  auto summary = std::make_unique<Label>();
  summary->setText(entry.summary);
  summary->setFontSize(kSummaryFontSize);
  summary->setColor(roleColor(isCritical ? ColorRole::OnError : ColorRole::OnSurface));
  summary->setBold(true);
  summary->setMaxWidth(innerWidth);
  summary->setMaxLines(kMaxSummaryLines);
  summary->measure(*m_renderContext);
  summary->setPosition(kCardInnerPad, kCardInnerPad + kCloseButtonSize + kMetaGap);
  *outSummary = summary.get();
  area->addChild(std::move(summary));

  // Body text — Pango handles wrap + ellipsize.
  auto body = std::make_unique<Label>();
  body->setText(entry.body);
  body->setFontSize(kBodyFontSize);
  body->setColor(roleColor(isCritical ? ColorRole::OnError : ColorRole::OnSurfaceVariant));
  body->setMaxWidth(innerWidth);
  body->setMaxLines(kMaxBodyLines);
  body->measure(*m_renderContext);
  body->setPosition(kCardInnerPad,
                    kCardInnerPad + kCloseButtonSize + kMetaGap + entry.summaryHeight + kSummaryBodyGap);
  *outBody = body.get();
  area->addChild(std::move(body));

  // Progress bar (countdown)
  auto progressBar = std::make_unique<ProgressBar>();
  progressBar->setSize(innerWidth, kProgressHeight);
  progressBar->setPosition(kCardInnerPad, progressY);
  *outProgress = static_cast<ProgressBar*>(area->addChild(std::move(progressBar)));

  return area.release();
}

// --- Pointer events ---

bool NotificationToast::onPointerEvent(const PointerEvent& event) {
  bool consumed = false;

  for (auto& inst : m_instances) {
    switch (event.type) {
    case PointerEvent::Type::Enter:
      if (event.surface == inst->surface->wlSurface()) {
        inst->pointerInside = true;
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
        inst->inputDispatcher.pointerMotion(static_cast<float>(event.sx), static_cast<float>(event.sy), 0);
      }
      break;
    case PointerEvent::Type::Button:
      if (inst->pointerInside) {
        bool pressed = (event.state == 1);
        inst->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                            pressed);
        consumed = true;
      }
      break;
    case PointerEvent::Type::Axis:
      break;
    }

    if (inst->sceneRoot != nullptr && inst->sceneRoot->dirty()) {
      inst->surface->requestRedraw();
    }
  }

  return consumed;
}
