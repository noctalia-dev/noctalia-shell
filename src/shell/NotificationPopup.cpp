#include "shell/NotificationPopup.h"

#include "config/ConfigService.h"
#include "core/DeferredCall.h"
#include "core/Log.h"
#include "render/RenderContext.h"
#include "render/scene/InputArea.h"
#include "render/scene/RectNode.h"
#include "render/scene/TextNode.h"
#include "ui/Palette.h"
#include "ui/Style.h"
#include "wayland/WaylandConnection.h"
#include "wayland/WaylandSeat.h"

#include <algorithm>
#include <linux/input-event-codes.h>

namespace {

constexpr float kCardWidth = 340.0f;
constexpr float kCardHeight = 72.0f;
constexpr float kGap = 8.0f;
constexpr float kPadding = 12.0f;
constexpr float kPopupDurationMs = 8000.0f;
constexpr int kMaxVisible = 5;
constexpr float kProgressHeight = 3.0f;
constexpr float kCardInnerPad = 10.0f;

constexpr float kSurfaceWidth = kCardWidth + kPadding * 2;
constexpr float kSurfaceHeight = kCardHeight * kMaxVisible + kGap * (kMaxVisible - 1) + kPadding * 2;

} // namespace

NotificationPopup::NotificationPopup() = default;

NotificationPopup::~NotificationPopup() {
  if (m_notifications != nullptr && m_callbackToken >= 0) {
    m_notifications->removeEventCallback(m_callbackToken);
  }
}

void NotificationPopup::initialize(WaylandConnection& wayland, ConfigService* config,
                                   NotificationManager* notifications, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_notifications = notifications;
  m_renderContext = renderContext;

  m_callbackToken = m_notifications->addEventCallback(
      [this](const Notification& n, NotificationEvent event) { onNotificationEvent(n, event); });
}

// --- Notification events ---

void NotificationPopup::onNotificationEvent(const Notification& n, NotificationEvent event) {
  switch (event) {
  case NotificationEvent::Added:
    addPopup(n);
    break;
  case NotificationEvent::Updated: {
    for (std::size_t i = 0; i < m_entries.size(); ++i) {
      if (m_entries[i].notificationId == n.id && !m_entries[i].exiting) {
        m_entries[i].appName = n.app_name;
        m_entries[i].summary = n.summary;
        m_entries[i].body = n.body;

        // Update text nodes and reset countdown on each instance
        for (auto& inst : m_instances) {
          if (i >= inst->cards.size()) {
            continue;
          }
          auto& cs = inst->cards[i];
          if (cs.cardNode == nullptr) {
            continue;
          }

          auto& children = cs.cardNode->children();
          static_cast<TextNode*>(children[1].get())->setText(n.app_name);
          static_cast<TextNode*>(children[2].get())->setText(n.summary);
          static_cast<TextNode*>(children[3].get())->setText(n.body);

          // Reset countdown
          if (cs.countdownAnimId != 0) {
            inst->animations.cancel(cs.countdownAnimId);
          }
          cs.progressFill->setSize(kCardWidth - kCardInnerPad * 2, kProgressHeight);
          cs.countdownAnimId = inst->animations.animate(
              kCardWidth - kCardInnerPad * 2, 0.0f, kPopupDurationMs, Easing::Linear,
              [fill = cs.progressFill](float w) { fill->setSize(w, kProgressHeight); },
              [this, id = n.id]() { DeferredCall::callLater([this, id]() { removePopup(id); }); });

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

void NotificationPopup::addPopup(const Notification& n) {
  for (const auto& entry : m_entries) {
    if (entry.notificationId == n.id) {
      return;
    }
  }

  while (static_cast<int>(m_entries.size()) >= kMaxVisible) {
    dismissPopup(0);
  }

  ensureSurfaces();

  PopupEntry entry;
  entry.notificationId = n.id;
  entry.appName = n.app_name;
  entry.summary = n.summary;
  entry.body = n.body;
  entry.urgency = n.urgency;
  m_entries.push_back(std::move(entry));
  std::size_t index = m_entries.size() - 1;

  for (auto& inst : m_instances) {
    if (inst->sceneRoot == nullptr) {
      continue;
    }
    addCardToInstance(*inst, index);
  }

  logDebug("notification popup: showing #{} \"{}\"", n.id, n.summary);
}

void NotificationPopup::removePopup(uint32_t notificationId) {
  for (std::size_t i = 0; i < m_entries.size(); ++i) {
    if (m_entries[i].notificationId == notificationId && !m_entries[i].exiting) {
      dismissPopup(i);
      return;
    }
  }
}

void NotificationPopup::dismissPopup(std::size_t index) {
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

void NotificationPopup::finishRemoval(std::size_t index) {
  if (index >= m_entries.size()) {
    return;
  }

  // Remove card nodes from all instances
  for (auto& inst : m_instances) {
    if (index < inst->cards.size()) {
      Node* card = inst->cards[index].cardNode;
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

void NotificationPopup::addCardToInstance(PopupInstance& inst, std::size_t entryIndex) {
  auto& entry = m_entries[entryIndex];
  Node* card = buildCard(entry);

  float targetY = cardTargetY(entryIndex);
  card->setPosition(kPadding + 20.0f, targetY);
  card->setOpacity(0.0f);

  inst.sceneRoot->addChild(std::unique_ptr<Node>(card));

  PopupInstance::CardState cs;
  cs.cardNode = card;
  cs.progressFill = static_cast<RectNode*>(card->children()[5].get());

  // Entry animation
  cs.entryAnimId = inst.animations.animate(
      0.0f, 1.0f, Style::animNormal, Easing::EaseOutCubic,
      [card, targetY](float v) {
        card->setOpacity(v);
        card->setPosition(kPadding + 20.0f * (1.0f - v), targetY);
      },
      [&inst, entryIndex]() {
        if (entryIndex < inst.cards.size()) {
          inst.cards[entryIndex].entryAnimId = 0;
        }
      });

  // Countdown (only the first instance drives the timeout to avoid duplicate removals)
  float progressWidth = kCardWidth - kCardInnerPad * 2;
  bool isDriver = (m_instances.size() > 0 && m_instances[0].get() == &inst);
  cs.countdownAnimId = inst.animations.animate(
      progressWidth, 0.0f, kPopupDurationMs, Easing::Linear,
      [fill = cs.progressFill](float w) { fill->setSize(w, kProgressHeight); },
      [this, id = entry.notificationId, isDriver]() {
        if (isDriver) {
          DeferredCall::callLater([this, id]() { removePopup(id); });
        }
      });

  inst.cards.push_back(cs);
  inst.surface->requestRedraw();
}

void NotificationPopup::dismissCardFromInstance(PopupInstance& inst, std::size_t entryIndex) {
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

  Node* card = cs.cardNode;
  float startX = card->x();

  // Only the first instance drives finishRemoval
  bool isDriver = (m_instances.size() > 0 && m_instances[0].get() == &inst);
  inst.animations.animate(
      1.0f, 0.0f, Style::animNormal, Easing::EaseInOutQuad,
      [card, startX](float v) {
        card->setOpacity(v);
        card->setPosition(startX + 20.0f * (1.0f - v), card->y());
      },
      [this, entryIndex, isDriver]() {
        if (isDriver) {
          DeferredCall::callLater([this, entryIndex]() { finishRemoval(entryIndex); });
        }
      });

  inst.surface->requestRedraw();
}

void NotificationPopup::layoutCards(PopupInstance& inst) {
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

  inst.surface->requestRedraw();
}

float NotificationPopup::cardTargetY(std::size_t index) const {
  return kPadding + static_cast<float>(index) * (kCardHeight + kGap);
}

// --- Surface lifecycle ---

void NotificationPopup::ensureSurfaces() {
  if (!m_instances.empty()) {
    return;
  }
  if (m_wayland == nullptr || m_renderContext == nullptr) {
    return;
  }

  uint32_t barHeight = 42;
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

    bool ok = inst->surface->initialize(output.output, output.scale);
    if (!ok) {
      logWarn("notification popup: failed to initialize surface on {}", output.connectorName);
      continue;
    }

    inst->wlSurface = inst->surface->wlSurface();
    logDebug("notification popup: surface created on {}", output.connectorName);
    m_instances.push_back(std::move(inst));
  }
}

void NotificationPopup::destroySurfaces() {
  for (auto& inst : m_instances) {
    inst->animations.cancelAll();
    inst->inputDispatcher.setSceneRoot(nullptr);
  }
  m_instances.clear();
  m_entries.clear();
  logDebug("notification popup: all surfaces destroyed");
}

void NotificationPopup::buildScene(PopupInstance& inst, uint32_t width, uint32_t height) {
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
}

Node* NotificationPopup::buildCard(const PopupEntry& entry) {
  auto area = std::make_unique<InputArea>();
  area->setSize(kCardWidth, kCardHeight);
  area->setOnClick([this, id = entry.notificationId](const InputArea::PointerData& data) {
    if (data.button == BTN_LEFT) {
      removePopup(id);
    }
  });

  // [0] Background
  auto bg = std::make_unique<RectNode>();
  bg->setSize(kCardWidth, kCardHeight);
  bg->setStyle(RoundedRectStyle{
      .fill = palette.surface,
      .border = palette.outline,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });
  area->addChild(std::move(bg));

  // Text Y positions account for baseline rendering: the font's ascent (negative top metric)
  // pushes the visible glyphs below the node's Y coordinate.
  // Caption (11px): ascent ~9px, Body (13px): ascent ~11px
  constexpr float kCaptionAscent = 9.0f;
  constexpr float kBodyAscent = 11.0f;

  // [1] App name
  auto appName = std::make_unique<TextNode>();
  appName->setText(entry.appName);
  appName->setFontSize(Style::fontSizeCaption);
  appName->setColor(palette.onSurfaceVariant);
  appName->setPosition(kCardInnerPad, kCardInnerPad + kCaptionAscent);
  appName->setMaxWidth(kCardWidth - kCardInnerPad * 2);
  area->addChild(std::move(appName));

  // [2] Summary
  auto summary = std::make_unique<TextNode>();
  summary->setText(entry.summary);
  summary->setFontSize(Style::fontSizeBody);
  summary->setColor(palette.onSurface);
  summary->setPosition(kCardInnerPad, kCardInnerPad + Style::fontSizeCaption + 4.0f + kBodyAscent);
  summary->setMaxWidth(kCardWidth - kCardInnerPad * 2);
  area->addChild(std::move(summary));

  // [3] Body
  auto body = std::make_unique<TextNode>();
  body->setText(entry.body);
  body->setFontSize(Style::fontSizeCaption);
  body->setColor(palette.onSurfaceVariant);
  body->setPosition(kCardInnerPad,
                    kCardInnerPad + Style::fontSizeCaption + 4.0f + Style::fontSizeBody + 4.0f + kCaptionAscent);
  body->setMaxWidth(kCardWidth - kCardInnerPad * 2);
  area->addChild(std::move(body));

  // [4] Progress bar background
  float progressWidth = kCardWidth - kCardInnerPad * 2;
  float progressY = kCardHeight - kProgressHeight - 6.0f;

  auto progressBg = std::make_unique<RectNode>();
  progressBg->setSize(progressWidth, kProgressHeight);
  progressBg->setPosition(kCardInnerPad, progressY);
  progressBg->setStyle(RoundedRectStyle{
      .fill = palette.surfaceVariant,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusSm,
      .softness = 0.5f,
  });
  area->addChild(std::move(progressBg));

  // [5] Progress bar fill (countdown)
  auto progressFill = std::make_unique<RectNode>();
  progressFill->setSize(progressWidth, kProgressHeight);
  progressFill->setPosition(kCardInnerPad, progressY);
  progressFill->setStyle(RoundedRectStyle{
      .fill = palette.primary,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusSm,
      .softness = 0.5f,
  });
  area->addChild(std::move(progressFill));

  return area.release();
}

// --- Pointer events ---

void NotificationPopup::onPointerEvent(const PointerEvent& event) {
  for (auto& inst : m_instances) {
    switch (event.type) {
    case PointerEvent::Type::Enter:
      if (event.surface == inst->wlSurface) {
        inst->pointerInside = true;
        inst->inputDispatcher.pointerEnter(static_cast<float>(event.sx), static_cast<float>(event.sy), event.serial);
      }
      break;
    case PointerEvent::Type::Leave:
      if (event.surface == inst->wlSurface) {
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
      }
      break;
    }

    if (inst->sceneRoot != nullptr && inst->sceneRoot->dirty()) {
      inst->surface->requestRedraw();
    }
  }
}
