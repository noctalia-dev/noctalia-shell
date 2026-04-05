#include "shell/notification/notification_history_popup.h"

#include "config/config_service.h"
#include "core/deferred_call.h"
#include "notification/notification_manager.h"
#include "render/render_context.h"
#include "render/scene/input_area.h"
#include "render/scene/rect_node.h"
#include "render/scene/text_node.h"
#include "ui/controls/scroll_view.h"
#include "ui/palette.h"
#include "ui/style.h"
#include "wayland/wayland_connection.h"
#include "wayland/wayland_seat.h"

#include <algorithm>
#include <linux/input-event-codes.h>
#include <string>

namespace {

constexpr float kPanelWidth = 380.0f;
constexpr float kPadding = 12.0f;
constexpr float kHeaderHeight = 36.0f;
constexpr float kRowGap = 8.0f;
constexpr float kRowPadding = 10.0f;
constexpr float kMetaFontSize = 11.0f;
constexpr float kSummaryFontSize = 14.0f;
constexpr float kBodyFontSize = 12.0f;
constexpr float kMetaAscent = 9.0f;
constexpr float kSummaryAscent = 12.0f;
constexpr float kBodyAscent = 10.0f;
constexpr float kSummaryLineHeight = 16.0f;
constexpr float kBodyLineHeight = 14.0f;
constexpr std::size_t kMaxSummaryLines = 2;
constexpr std::size_t kMaxBodyLines = 3;
constexpr float kDismissButtonSize = 22.0f;
constexpr float kMinRowHeight = 76.0f;
constexpr float kEmptyHeight = 84.0f;
constexpr float kSurfaceWidth = kPanelWidth + kPadding * 2;
constexpr float kSurfaceMaxHeight = 640.0f;

std::string collapseWhitespace(std::string_view text) {
  std::string out;
  out.reserve(text.size());

  bool lastWasSpace = true;
  for (char ch : text) {
    const bool isWhitespace = (ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r');
    if (isWhitespace) {
      if (!lastWasSpace) {
        out.push_back(' ');
      }
      lastWasSpace = true;
      continue;
    }
    out.push_back(ch);
    lastWasSpace = false;
  }

  if (!out.empty() && out.back() == ' ') {
    out.pop_back();
  }
  return out;
}

std::string truncateToWidth(RenderContext& renderer, std::string text, float fontSize, float maxWidth) {
  static constexpr std::string_view kEllipsis = "\xe2\x80\xa6";
  if (renderer.measureText(text, fontSize).width <= maxWidth) {
    return text;
  }

  while (!text.empty()) {
    text.pop_back();
    std::string candidate = text + std::string(kEllipsis);
    if (renderer.measureText(candidate, fontSize).width <= maxWidth) {
      return candidate;
    }
  }

  return std::string(kEllipsis);
}

std::pair<std::string, std::size_t> wrapText(RenderContext* renderer, std::string_view text, float fontSize, float maxWidth,
                                             std::size_t maxLines) {
  const std::string normalized = collapseWhitespace(text);
  if (renderer == nullptr || normalized.empty()) {
    return {normalized, normalized.empty() ? 0u : 1u};
  }

  std::vector<std::string> words;
  std::size_t start = 0;
  while (start < normalized.size()) {
    const std::size_t end = normalized.find(' ', start);
    if (end == std::string::npos) {
      words.push_back(normalized.substr(start));
      break;
    }
    words.push_back(normalized.substr(start, end - start));
    start = end + 1;
  }

  std::vector<std::string> lines;
  lines.reserve(maxLines);

  std::size_t wordIndex = 0;
  while (wordIndex < words.size() && lines.size() < maxLines) {
    std::string line = words[wordIndex];
    if (renderer->measureText(line, fontSize).width > maxWidth) {
      line = truncateToWidth(*renderer, line, fontSize, maxWidth);
      lines.push_back(std::move(line));
      ++wordIndex;
      continue;
    }

    std::size_t nextIndex = wordIndex + 1;
    while (nextIndex < words.size()) {
      const std::string candidate = line + " " + words[nextIndex];
      if (renderer->measureText(candidate, fontSize).width > maxWidth) {
        break;
      }
      line = candidate;
      ++nextIndex;
    }

    if (lines.size() + 1 == maxLines && nextIndex < words.size()) {
      std::string remainder = line;
      for (std::size_t i = nextIndex; i < words.size(); ++i) {
        remainder += " ";
        remainder += words[i];
      }
      line = truncateToWidth(*renderer, remainder, fontSize, maxWidth);
      nextIndex = words.size();
    }

    lines.push_back(std::move(line));
    wordIndex = nextIndex;
  }

  std::string wrapped;
  for (std::size_t i = 0; i < lines.size(); ++i) {
    if (i > 0) {
      wrapped.push_back('\n');
    }
    wrapped += lines[i];
  }

  return {wrapped, std::max<std::size_t>(1, lines.size())};
}

float notificationRowHeight(const Notification& notification, RenderContext* renderer, float textWidth) {
  const auto [wrappedSummary, summaryLines] =
      wrapText(renderer, notification.summary, kSummaryFontSize, textWidth, kMaxSummaryLines);
  (void)wrappedSummary;
  const auto [wrappedBody, bodyLines] = wrapText(renderer, notification.body, kBodyFontSize, textWidth, kMaxBodyLines);
  (void)wrappedBody;

  const float contentHeight =
      kRowPadding + kMetaFontSize + 3.0f + static_cast<float>(summaryLines) * kSummaryLineHeight + 2.0f +
      static_cast<float>(std::max<std::size_t>(1, bodyLines)) * kBodyLineHeight + kRowPadding;
  return std::max(kMinRowHeight, contentHeight);
}

} // namespace

NotificationHistoryPopup::~NotificationHistoryPopup() {
  if (m_notifications != nullptr && m_callbackToken >= 0) {
    m_notifications->removeEventCallback(m_callbackToken);
  }
}

void NotificationHistoryPopup::initialize(WaylandConnection& wayland, ConfigService* config,
                                          NotificationManager* notifications, RenderContext* renderContext) {
  m_wayland = &wayland;
  m_config = config;
  m_notifications = notifications;
  m_renderContext = renderContext;

  if (m_notifications != nullptr) {
    m_callbackToken = m_notifications->addEventCallback(
        [this](const Notification& notification, NotificationEvent event) { onNotificationEvent(notification, event); });
  }
}

void NotificationHistoryPopup::toggleFromWidgetPress() {
  m_ignoreNextOutsidePress = true;
  toggle();
}

void NotificationHistoryPopup::toggle() {
  if (m_visible) {
    close();
    return;
  }

  refreshNotifications();
  m_visible = true;
  ensureSurfaces();
  rebuildScenes();
}

void NotificationHistoryPopup::close() {
  if (!m_visible) {
    return;
  }

  m_visible = false;
  destroySurfaces();
}

bool NotificationHistoryPopup::onPointerEvent(const PointerEvent& event) {
  if (!m_visible) {
    return false;
  }

  if (event.type == PointerEvent::Type::Button && event.state == 1 && m_ignoreNextOutsidePress) {
    m_ignoreNextOutsidePress = false;
    return false;
  }

  if (event.type == PointerEvent::Type::Button && event.state == 1 && !ownsSurface(event.surface)) {
    close();
    return false;
  }

  bool consumed = false;
  for (std::size_t i = 0; i < m_instances.size(); ++i) {
    auto* inst = m_instances[i].get();
    if (inst == nullptr) {
      continue;
    }

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
        consumed = true;
      }
      break;
    case PointerEvent::Type::Button:
      if (inst->pointerInside) {
        const bool pressed = (event.state == 1);
        inst->inputDispatcher.pointerButton(static_cast<float>(event.sx), static_cast<float>(event.sy), event.button,
                                            pressed);
        consumed = true;
        if (!m_visible || m_instances.empty()) {
          return consumed;
        }
      }
      break;
    case PointerEvent::Type::Axis:
      if (inst->pointerInside) {
        consumed = inst->inputDispatcher.pointerAxis(static_cast<float>(event.sx), static_cast<float>(event.sy),
                                                     event.axis, static_cast<float>(event.axisValue),
                                                     event.axisDiscrete) ||
                   consumed;
      }
      break;
    }

    if (event.type != PointerEvent::Type::Button && inst->surface != nullptr && inst->sceneRoot != nullptr &&
        inst->sceneRoot->dirty()) {
      inst->surface->requestRedraw();
    }
  }

  return consumed;
}

void NotificationHistoryPopup::refreshNotifications() {
  m_items.clear();
  if (m_notifications == nullptr) {
    return;
  }

  const auto& all = m_notifications->all();
  m_items.reserve(all.size());
  for (auto it = all.rbegin(); it != all.rend(); ++it) {
    m_items.push_back(*it);
  }
}

void NotificationHistoryPopup::onNotificationEvent(const Notification& /*notification*/, NotificationEvent /*event*/) {
  if (!m_visible) {
    return;
  }
  if (m_suppressRebuild) {
    return;
  }

  refreshNotifications();
  rebuildScenes();
}

bool NotificationHistoryPopup::ownsSurface(wl_surface* surface) const {
  if (surface == nullptr) {
    return false;
  }

  return std::any_of(m_instances.begin(), m_instances.end(),
                     [surface](const auto& inst) { return inst != nullptr && inst->wlSurface == surface; });
}

uint32_t NotificationHistoryPopup::surfaceHeightPx() const {
  float height = kPadding * 2 + kHeaderHeight;

  if (m_items.empty()) {
    height += kEmptyHeight;
  } else {
    const float textWidth = kPanelWidth - kRowPadding * 2 - kDismissButtonSize - 10.0f;
    for (std::size_t i = 0; i < m_items.size(); ++i) {
      if (i > 0) {
        height += kRowGap;
      }
      height += notificationRowHeight(m_items[i], m_renderContext, textWidth);
    }
  }

  return static_cast<uint32_t>(std::min(height, kSurfaceMaxHeight));
}

void NotificationHistoryPopup::ensureSurfaces() {
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

  const auto surfaceWidth = static_cast<uint32_t>(kSurfaceWidth);
  const auto surfaceHeight = static_cast<uint32_t>(kSurfaceMaxHeight);

  for (const auto& output : m_wayland->outputs()) {
    auto inst = std::make_unique<PopupInstance>();
    inst->output = output.output;
    inst->scale = output.scale;

    auto surfaceConfig = LayerSurfaceConfig{
        .nameSpace = "noctalia-notification-history",
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
    inst->surface->setRenderContext(m_renderContext);

    if (!inst->surface->initialize(output.output, output.scale)) {
      continue;
    }

    inst->wlSurface = inst->surface->wlSurface();
    m_instances.push_back(std::move(inst));
  }
}

void NotificationHistoryPopup::destroySurfaces() {
  for (auto& inst : m_instances) {
    inst->inputDispatcher.setSceneRoot(nullptr);
  }
  m_instances.clear();
}

void NotificationHistoryPopup::rebuildScenes() {
  if (!m_visible) {
    return;
  }

  if (m_instances.empty()) {
    ensureSurfaces();
  }
  if (m_instances.empty()) {
    return;
  }

  const auto height = m_instances.front()->surface != nullptr ? m_instances.front()->surface->height()
                                                              : surfaceHeightPx();
  refreshNotifications();
  for (auto& inst : m_instances) {
    buildScene(*inst, static_cast<uint32_t>(kSurfaceWidth), height);
    if (inst->surface != nullptr) {
      inst->surface->requestRedraw();
    }
  }
}

void NotificationHistoryPopup::buildScene(PopupInstance& inst, uint32_t width, uint32_t height) {
  const float w = static_cast<float>(width);
  const float h = static_cast<float>(std::max(height, surfaceHeightPx()));

  inst.sceneRoot = std::make_unique<Node>();
  inst.sceneRoot->setSize(w, h);

  auto bg = std::make_unique<RectNode>();
  bg->setSize(w, h);
  bg->setStyle(RoundedRectStyle{
      .fill = palette.surface,
      .border = palette.outline,
      .fillMode = FillMode::Solid,
      .radius = Style::radiusMd,
      .softness = 1.0f,
      .borderWidth = Style::borderWidth,
  });
  inst.sceneRoot->addChild(std::move(bg));

  auto title = std::make_unique<TextNode>();
  title->setText("Notifications");
  title->setFontSize(Style::fontSizeBody);
  title->setColor(palette.onSurface);
  title->setPosition(kPadding, kPadding + 11.0f);
  inst.sceneRoot->addChild(std::move(title));

  if (!m_items.empty()) {
    auto clearArea = std::make_unique<InputArea>();
    clearArea->setSize(72.0f, 24.0f);
    clearArea->setPosition(w - kPadding - 72.0f, kPadding);
    clearArea->setOnClick([this](const InputArea::PointerData& data) {
      if (data.button == BTN_LEFT) {
        DeferredCall::callLater([this]() {
          m_suppressRebuild = true;
          if (m_notifications != nullptr) {
            m_notifications->closeAll(CloseReason::Dismissed);
          }
          m_suppressRebuild = false;
          if (m_visible) {
            refreshNotifications();
            rebuildScenes();
          }
        });
      }
    });

    auto clearBg = std::make_unique<RectNode>();
    clearBg->setSize(72.0f, 24.0f);
    clearBg->setStyle(RoundedRectStyle{
        .fill = palette.surfaceVariant,
        .fillMode = FillMode::Solid,
        .radius = Style::radiusSm,
        .softness = 1.0f,
    });
    clearArea->addChild(std::move(clearBg));

    auto clearText = std::make_unique<TextNode>();
    clearText->setText("Clear all");
    clearText->setFontSize(Style::fontSizeCaption);
    clearText->setColor(palette.onSurfaceVariant);
    clearText->setPosition(10.0f, 7.0f + 9.0f);
    clearArea->addChild(std::move(clearText));
    inst.sceneRoot->addChild(std::move(clearArea));
  }

  const float listY = kPadding + kHeaderHeight;
  const float rowWidth = kPanelWidth;
  const float textWidth = rowWidth - kRowPadding * 2 - kDismissButtonSize - 10.0f;
  const float listHeight = std::max(0.0f, h - listY - kPadding);

  auto scrollView = std::make_unique<ScrollView>();
  scrollView->setPosition(kPadding, listY);
  scrollView->setSize(rowWidth, listHeight);
  scrollView->setScrollbarVisible(!m_items.empty());
  scrollView->content()->setDirection(BoxDirection::Vertical);
  scrollView->content()->setAlign(BoxAlign::Start);
  scrollView->content()->setGap(kRowGap);

  if (m_items.empty()) {
    auto row = std::make_unique<Node>();
    row->setSize(rowWidth, kEmptyHeight);

    auto empty = std::make_unique<TextNode>();
    empty->setText("No notifications");
    empty->setFontSize(Style::fontSizeBody);
    empty->setColor(palette.onSurfaceVariant);
    empty->setPosition(kPadding, 22.0f);
    empty->setMaxWidth(kPanelWidth);
    row->addChild(std::move(empty));

    scrollView->content()->addChild(std::move(row));
  } else {
    for (const auto& notification : m_items) {
      const auto [wrappedSummary, summaryLines] =
          wrapText(m_renderContext, notification.summary, kSummaryFontSize, textWidth, kMaxSummaryLines);
      const auto [wrappedBody, bodyLines] =
          wrapText(m_renderContext, notification.body, kBodyFontSize, textWidth, kMaxBodyLines);
      const float rowHeight = notificationRowHeight(notification, m_renderContext, textWidth);

      auto row = std::make_unique<InputArea>();
      row->setSize(rowWidth, rowHeight);

      auto rowBg = std::make_unique<RectNode>();
      rowBg->setSize(rowWidth, rowHeight);
      rowBg->setStyle(RoundedRectStyle{
          .fill = palette.surfaceVariant,
          .fillMode = FillMode::Solid,
          .radius = Style::radiusMd,
          .softness = 1.0f,
      });
      row->addChild(std::move(rowBg));

      auto appName = std::make_unique<TextNode>();
      appName->setText(notification.appName);
      appName->setFontSize(kMetaFontSize);
      appName->setColor(palette.onSurfaceVariant);
      appName->setPosition(kRowPadding, kRowPadding + kMetaAscent);
      appName->setMaxWidth(textWidth);
      row->addChild(std::move(appName));

      auto summary = std::make_unique<TextNode>();
      summary->setText(wrappedSummary);
      summary->setFontSize(kSummaryFontSize);
      summary->setColor(palette.onSurface);
      summary->setPosition(kRowPadding, kRowPadding + kMetaFontSize + 3.0f + kSummaryAscent);
      row->addChild(std::move(summary));

      auto body = std::make_unique<TextNode>();
      body->setText(wrappedBody);
      body->setFontSize(kBodyFontSize);
      body->setColor(palette.onSurfaceVariant);
      body->setPosition(kRowPadding, kRowPadding + kMetaFontSize + 3.0f +
                                         static_cast<float>(summaryLines) * kSummaryLineHeight + 2.0f + kBodyAscent);
      row->addChild(std::move(body));

      auto dismissArea = std::make_unique<InputArea>();
      dismissArea->setSize(kDismissButtonSize, kDismissButtonSize);
      dismissArea->setPosition(rowWidth - kRowPadding - kDismissButtonSize, kRowPadding);
      dismissArea->setOnClick([this, id = notification.id](const InputArea::PointerData& data) {
        if (data.button == BTN_LEFT) {
          DeferredCall::callLater([this, id]() {
            if (m_notifications != nullptr) {
              (void)m_notifications->close(id, CloseReason::Dismissed);
            }
          });
        }
      });

      auto dismissBg = std::make_unique<RectNode>();
      dismissBg->setSize(kDismissButtonSize, kDismissButtonSize);
      dismissBg->setStyle(RoundedRectStyle{
          .fill = palette.surface,
          .fillMode = FillMode::Solid,
          .radius = Style::radiusSm,
          .softness = 1.0f,
      });
      dismissArea->addChild(std::move(dismissBg));

      auto dismissText = std::make_unique<TextNode>();
      dismissText->setText("x");
      dismissText->setFontSize(Style::fontSizeBody);
      dismissText->setColor(palette.onSurfaceVariant);
      dismissText->setPosition(7.0f, 4.0f + 11.0f);
      dismissArea->addChild(std::move(dismissText));
      row->addChild(std::move(dismissArea));

      scrollView->content()->addChild(std::move(row));
    }
  }

  if (m_renderContext != nullptr) {
    scrollView->layout(*m_renderContext);
  }
  inst.sceneRoot->addChild(std::move(scrollView));

  inst.inputDispatcher.setSceneRoot(inst.sceneRoot.get());
  inst.inputDispatcher.setCursorShapeCallback(
      [this](uint32_t serial, uint32_t shape) { m_wayland->setCursorShape(serial, shape); });
  inst.surface->setSceneRoot(inst.sceneRoot.get());
}
