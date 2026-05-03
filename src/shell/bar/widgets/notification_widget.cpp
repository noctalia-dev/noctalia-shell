#include "shell/bar/widgets/notification_widget.h"

#include "notification/notification_manager.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "ui/controls/box.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <linux/input-event-codes.h>
#include <memory>

namespace {
  constexpr float kDotBaseSize = 6.0f;
} // namespace

NotificationWidget::NotificationWidget(NotificationManager* manager, wl_output* output)
    : m_manager(manager), m_output(output) {}

void NotificationWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& data) {
    if (data.button == BTN_RIGHT) {
      if (m_manager != nullptr) {
        const bool dndEnabled = m_manager->toggleDoNotDisturb();
        (void)dndEnabled;
      }
      requestRedraw();
      return;
    }
    if (data.button != BTN_LEFT) {
      return;
    }
    requestPanelToggle("control-center", "notifications");
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("bell");
  glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  auto dot = std::make_unique<Box>();
  dot->setFill(colorSpecFromRole(ColorRole::Primary));
  const float dotSize = kDotBaseSize * m_contentScale;
  dot->setRadius(dotSize * 0.5f);
  dot->setSize(dotSize, dotSize);
  dot->setVisible(false);
  m_dot = area->addChild(std::move(dot));

  setRoot(std::move(area));
  refreshIndicatorState();
}

void NotificationWidget::doLayout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_glyph == nullptr || rootNode == nullptr) {
    return;
  }

  refreshIndicatorState();

  m_glyph->setGlyphSize(Style::barGlyphSize * m_contentScale);
  m_glyph->setGlyph(m_dndEnabled ? "bell-off" : "bell");
  m_glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  m_glyph->measure(renderer);
  m_glyph->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_glyph->width(), m_glyph->height());

  if (m_dot != nullptr) {
    const float dotSize = kDotBaseSize * m_contentScale;
    m_dot->setPosition(m_glyph->width() - dotSize, 0.0f);
  }
}

void NotificationWidget::doUpdate(Renderer& /*renderer*/) { refreshIndicatorState(); }

void NotificationWidget::refreshIndicatorState() {
  const bool hasNotifications = (m_manager != nullptr) && m_manager->hasUnreadNotificationHistory();
  const bool dndEnabled = (m_manager != nullptr) && m_manager->doNotDisturb();
  if (hasNotifications == m_hasNotifications && dndEnabled == m_dndEnabled) {
    return;
  }
  m_hasNotifications = hasNotifications;
  m_dndEnabled = dndEnabled;
  if (m_glyph != nullptr) {
    m_glyph->setGlyph(m_dndEnabled ? "bell-off" : "bell");
    m_glyph->setColor(widgetForegroundOr(colorSpecFromRole(ColorRole::OnSurface)));
  }
  if (m_dot != nullptr) {
    m_dot->setVisible(m_hasNotifications && !m_dndEnabled);
  }
}
