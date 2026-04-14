#include "core/ui_phase.h"
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
constexpr int kCardHeight = 130;

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
constexpr float kBodyBottomGap = Style::spaceSm;           // gap between body text and progress bar

constexpr float kMetaFontSize = Style::fontSizeCaption;
constexpr float kSummaryFontSize = Style::fontSizeTitle;
constexpr float kBodyFontSize = Style::fontSizeBody;

constexpr float kMetaGap = Style::spaceXs;        // vertical gap between app name and summary
constexpr float kSummaryBodyGap = Style::spaceXs; // vertical gap between summary and body

constexpr std::size_t kMaxSummaryLines = 2;
constexpr std::size_t kMaxBodyLines = 3;

constexpr int kSurfaceWidth = static_cast<int>(kCardWidth + kPadding * 2);
constexpr int kSurfaceHeight = static_cast<int>(kCardHeight * kMaxVisible + kGap * (kMaxVisible - 1) + kPadding * 2);

int fitBodyLines(RenderContext& renderContext, float summaryHeight) {
  const float progressY = static_cast<float>(kCardHeight) - kProgressHeight - kProgressBottomMargin;
  const float bodyTop = kCardInnerPad + kCloseButtonSize + kMetaGap + summaryHeight + kSummaryBodyGap;
  const float availableHeight = progressY - kBodyBottomGap - bodyTop;
  if (availableHeight <= 0.0f) {
    return 0;
  }

  const auto metrics = renderContext.measureText("A", kBodyFontSize);
  const float lineHeight = std::max(1.0f, metrics.bottom - metrics.top);
  return std::clamp(static_cast<int>(std::floor((availableHeight + 0.5f) / lineHeight)), 0,
                    static_cast<int>(kMaxBodyLines));
}

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
        const bool hovered = m_entries[i].hovered;

        // Update text nodes and reset countdown on each instance
        for (auto& inst : m_instances) {
          if (i >= inst->cards.size()) {
            continue;
          }
          auto& cs = inst->cards[i];
          if (cs.cardNode == nullptr) {
            continue;
          }

          cs.appNameLabel->setText(n.appName);
          cs.summaryLabel->setText(m_entries[i].summary);
          cs.summaryLabel->measure(*m_renderContext);
          const int bodyLines = fitBodyLines(*m_renderContext, cs.summaryLabel->height());
          cs.bodyLabel->setMaxLines(std::max(1, bodyLines));
          cs.bodyLabel->setText(bodyLines > 0 ? m_entries[i].body : "");
          cs.bodyLabel->measure(*m_renderContext);
          cs.bodyLabel->setVisible(bodyLines > 0 && !m_entries[i].body.empty());
          cs.bodyLabel->setPosition(kCardInnerPad,
                                    kCardInnerPad + kCloseButtonSize + kMetaGap +
                                        cs.summaryLabel->height() + kSummaryBodyGap);

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
              cs.countdownAnimId = inst->animations.animate(
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
          cs.cardNode->setOpacity(0.7f);
          inst->animations.animate(0.7f, 1.0f, Style::animFast, Easing::EaseOutCubic,
                                   [card = cs.cardNode](float v) { card->setOpacity(v); }, {}, cs.cardNode);

          inst->surface->requestRedraw();
        }
        if (hovered && m_notifications != nullptr) {
          m_notifications->pauseExpiry(n.id);
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

  std::size_t slot = findFreeSlot();
  if (slot >= kMaxVisible) {
    // Keep overflow queued off-screen and reveal it when a real visible slot opens.
    slot = kMaxVisible;
  }

  ensureSurfaces();

  PopupEntry entry;
  entry.notificationId = n.id;
  entry.appName = n.appName;
  entry.summary = n.summary;
  entry.body = n.body;
  entry.urgency = n.urgency;
  entry.displayDurationMs = resolveDisplayDuration(n.timeout);
  entry.remainingProgress = 1.0f;
  entry.slot = slot;
  m_entries.push_back(std::move(entry));
  std::size_t index = m_entries.size() - 1;

  for (auto& inst : m_instances) {
    if (inst->sceneRoot == nullptr) {
      continue;
    }
    inst->cards.resize(m_entries.size());
    if (m_entries[index].slot < kMaxVisible) {
      addCardToInstance(*inst, index);
    }
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
    revealQueuedEntries();
  }
}

// --- Per-instance card management ---

void NotificationToast::addCardToInstance(PopupInstance& inst, std::size_t entryIndex) {
  auto& entry = m_entries[entryIndex];
  if (entry.slot >= kMaxVisible) {
    return;
  }

  if (entryIndex >= inst.cards.size()) {
    inst.cards.resize(entryIndex + 1);
  }

  auto& cs = inst.cards[entryIndex];
  cs = {};
  InputArea* card =
      buildCard(entry, &cs.appNameLabel, &cs.summaryLabel, &cs.bodyLabel, &cs.cardBg, &cs.progressBar, &cs.closeGlyph);
  cs.cardNode = card;

  float targetY = cardTargetY(entry.slot);
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
      },
      card);

  // Countdown (only the first instance drives the timeout to avoid duplicate removals)
  bool isDriver = (m_instances.size() > 0 && m_instances[0].get() == &inst);
  if (entry.displayDurationMs < 0) {
    // Persistent — no countdown, no auto-dismiss
    cs.progressBar->setOpacity(0.0f);
    cs.countdownAnimId = 0;
  } else {
    const float startProgress = std::clamp(entry.remainingProgress, 0.0f, 1.0f);
    cs.progressBar->setOpacity(1.0f);
    cs.progressBar->setProgress(startProgress);
    cs.countdownAnimId = inst.animations.animate(
        startProgress, 0.0f, static_cast<float>(entry.displayDurationMs) * startProgress, Easing::Linear,
        [this, pb = cs.progressBar, notificationId = entry.notificationId](float v) {
          pb->setProgress(v);
          if (auto* popup = findEntry(notificationId); popup != nullptr) {
            popup->remainingProgress = v;
          }
        },
        [this, id = entry.notificationId, isDriver]() {
          if (isDriver) {
            DeferredCall::callLater([this, id]() { removePopup(id); });
          }
        },
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
  if (cs.cardNode == nullptr) {
    return;
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
      },
      card);

  updateInputRegion(inst);
  inst.surface->requestRedraw();
}

void NotificationToast::layoutCards(PopupInstance& inst) {
  // Reflow is intentionally snapped rather than animated. Notifications are transient
  // UI and slide-up reordering makes hover/freeze behavior harder to track.
  for (std::size_t i = 0; i < inst.cards.size(); ++i) {
    auto& cs = inst.cards[i];
    if (i >= m_entries.size() || m_entries[i].exiting || m_entries[i].slot >= kMaxVisible) {
      continue;
    }
    if (cs.cardNode == nullptr) {
      continue;
    }

    float targetY = cardTargetY(m_entries[i].slot);
    float currentY = cs.cardNode->y();
    if (std::abs(currentY - targetY) < 0.5f) {
      continue;
    }

    if (cs.slideAnimId != 0) {
      inst.animations.cancel(cs.slideAnimId);
      cs.slideAnimId = 0;
    }
    cs.cardNode->setPosition(cs.cardNode->x(), targetY);
  }

  updateInputRegion(inst);
  inst.surface->requestRedraw();
}

float NotificationToast::cardTargetY(std::size_t slot) const {
  return kPadding + static_cast<float>(slot) * (static_cast<float>(kCardHeight) + kGap);
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

NotificationToast::PopupInstance::CardState* NotificationToast::findCardState(PopupInstance& inst,
                                                                               uint32_t notificationId) {
  for (std::size_t i = 0; i < inst.cards.size() && i < m_entries.size(); ++i) {
    if (m_entries[i].notificationId == notificationId) {
      return &inst.cards[i];
    }
  }
  return nullptr;
}

void NotificationToast::pauseCountdowns(uint32_t notificationId) {
  for (auto& inst : m_instances) {
    auto* state = findCardState(*inst, notificationId);
    if (state == nullptr || state->countdownAnimId == 0) {
      continue;
    }
    inst->animations.cancel(state->countdownAnimId);
    state->countdownAnimId = 0;
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
    state->countdownAnimId = inst->animations.animate(
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
  while (true) {
    const std::size_t slot = findFreeSlot();
    if (slot >= kMaxVisible) {
      break;
    }

    const auto it = std::find_if(m_entries.begin(), m_entries.end(), [](const PopupEntry& entry) {
      return !entry.exiting && entry.slot >= kMaxVisible;
    });
    if (it == m_entries.end()) {
      break;
    }

    const std::size_t entryIndex = static_cast<std::size_t>(std::distance(m_entries.begin(), it));
    it->slot = slot;
    for (auto& inst : m_instances) {
      if (inst->sceneRoot == nullptr) {
        continue;
      }
      if (entryIndex >= inst->cards.size()) {
        inst->cards.resize(m_entries.size());
      }
      addCardToInstance(*inst, entryIndex);
    }
  }
}

std::size_t NotificationToast::findFreeSlot() const {
  for (std::size_t s = 0; s < kMaxVisible; ++s) {
    bool taken = false;
    for (const auto& e : m_entries) {
      if (!e.exiting && e.slot == s) {
        taken = true;
        break;
      }
    }
    if (!taken) {
      return s;
    }
  }
  return kMaxVisible;
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
    inst->surface->setConfigureCallback(
        [instPtr](uint32_t /*w*/, uint32_t /*h*/) { instPtr->surface->requestLayout(); });
    inst->surface->setPrepareFrameCallback(
        [this, instPtr](bool needsUpdate, bool needsLayout) { prepareFrame(*instPtr, needsUpdate, needsLayout); });
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

void NotificationToast::prepareFrame(PopupInstance& inst, bool /*needsUpdate*/, bool needsLayout) {
  if (m_renderContext == nullptr || inst.surface == nullptr) {
    return;
  }

  const auto width = inst.surface->width();
  const auto height = inst.surface->height();
  if (width == 0 || height == 0) {
    return;
  }

  m_renderContext->makeCurrent(inst.surface->renderTarget());

  const bool needsSceneBuild =
      inst.sceneRoot == nullptr || static_cast<uint32_t>(std::round(inst.sceneRoot->width())) != width ||
      static_cast<uint32_t>(std::round(inst.sceneRoot->height())) != height;
  if (needsSceneBuild || needsLayout) {
    UiPhaseScope layoutPhase(UiPhase::Layout);
    buildScene(inst, width, height);
  }
}

void NotificationToast::buildScene(PopupInstance& inst, uint32_t width, uint32_t height) {
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
    if (!m_entries[i].exiting && m_entries[i].slot < kMaxVisible) {
      addCardToInstance(inst, i);
    }
  }

  updateInputRegion(inst);
  if (inst.pointerInside) {
    inst.inputDispatcher.pointerMotion(inst.lastPointerX, inst.lastPointerY, 0);
  }
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

InputArea* NotificationToast::buildCard(const PopupEntry& entry, Label** outAppName, Label** outSummary,
                                        Label** outBody, Node** outBg, ProgressBar** outProgress,
                                        Glyph** outCloseGlyph) {
  const float innerWidth = kCardWidth - kCardInnerPad * 2;
  const float progressY = static_cast<float>(kCardHeight) - kProgressHeight - kProgressBottomMargin;

  auto area = std::make_unique<InputArea>();
  area->setSize(kCardWidth, static_cast<float>(kCardHeight));
  // Unified close mechanism: clicking anywhere on the card dismisses it. The (X) glyph
  // is purely visual — it brightens while the card is hovered via the card's own
  // onEnter/onLeave handlers installed in addCardToInstance().
  area->setOnClick([this, id = entry.notificationId](const InputArea::PointerData& data) {
    if (data.button == BTN_LEFT) {
      removePopup(id);
    }
  });

  const bool isCritical = (entry.urgency == Urgency::Critical);

  // Background
  auto bg = std::make_unique<Box>();
  bg->setCardStyle();
  bg->setRadius(Style::radiusXl);
  bg->setSoftness(1.25f);
  if (isCritical) {
    // Keep critical toasts readable: solid surface background + urgent border.
    bg->setFill(roleColor(ColorRole::Surface, 0.97f));
    bg->setBorder(roleColor(ColorRole::Error, 0.95f), Style::borderWidth * 1.4f);
  } else {
    bg->setFill(roleColor(ColorRole::Surface, 0.97f));
    bg->setBorder(roleColor(ColorRole::Outline, 0.8f), Style::borderWidth);
  }
  bg->setSize(kCardWidth, static_cast<float>(kCardHeight));
  *outBg = area->addChild(std::move(bg));

  // Header row: app name (left) + close glyph (right), vertically centred via Flex
  auto headerRow = std::make_unique<Flex>();
  headerRow->setDirection(FlexDirection::Horizontal);
  headerRow->setJustify(FlexJustify::SpaceBetween);
  headerRow->setAlign(FlexAlign::Center);
  headerRow->setSize(innerWidth, kCloseButtonSize);
  headerRow->setPosition(kCardInnerPad, kCardInnerPad);

  auto appName = std::make_unique<Label>();
  appName->setText(entry.appName);
  appName->setFontSize(kMetaFontSize);
  appName->setColor(roleColor(isCritical ? ColorRole::Error : ColorRole::OnSurfaceVariant));
  appName->measure(*m_renderContext);
  *outAppName = appName.get();
  headerRow->addChild(std::move(appName));

  auto closeGlyph = std::make_unique<Glyph>();
  closeGlyph->setGlyph("close");
  closeGlyph->setGlyphSize(kCloseGlyphSize);
  closeGlyph->setColor(resolveThemeColor(
      isCritical ? roleColor(ColorRole::Error, 0.75f) : roleColor(ColorRole::OnSurfaceVariant, 0.6f)));
  *outCloseGlyph = static_cast<Glyph*>(headerRow->addChild(std::move(closeGlyph)));
  headerRow->layout(*m_renderContext);

  area->addChild(std::move(headerRow));

  // Summary (bold title) — Pango handles wrap + ellipsize.
  auto summary = std::make_unique<Label>();
  summary->setText(entry.summary);
  summary->setFontSize(kSummaryFontSize);
  summary->setColor(roleColor(ColorRole::OnSurface));
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
  body->setColor(roleColor(ColorRole::OnSurfaceVariant));
  body->setMaxWidth(innerWidth);
  const int bodyLines = fitBodyLines(*m_renderContext, (*outSummary)->height());
  body->setMaxLines(std::max(1, bodyLines));
  if (bodyLines <= 0) {
    body->setText("");
    body->setVisible(false);
  }
  body->measure(*m_renderContext);
  body->setPosition(kCardInnerPad,
                    kCardInnerPad + kCloseButtonSize + kMetaGap + (*outSummary)->height() + kSummaryBodyGap);
  *outBody = body.get();
  area->addChild(std::move(body));

  // Progress bar (countdown)
  auto progressBar = std::make_unique<ProgressBar>();
  progressBar->setTrackColor(roleColor(ColorRole::OnSurfaceVariant, 0.35f));
  progressBar->setFillColor(roleColor(isCritical ? ColorRole::Error : ColorRole::Primary));
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
