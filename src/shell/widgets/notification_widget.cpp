#include "shell/widgets/notification_widget.h"

#include "notification/notification_manager.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/box.h"
#include "ui/controls/glyph.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <memory>

namespace {
constexpr float kDotBaseSize = 6.0f;
} // namespace

NotificationWidget::NotificationWidget(NotificationManager* manager, wl_output* output)
    : m_manager(manager), m_output(output) {}

void NotificationWidget::create() {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    PanelManager::instance().togglePanel("control-center", m_output, 0.0f, 0.0f, "notifications");
  });

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("bell");
  glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph = glyph.get();
  area->addChild(std::move(glyph));

  auto dot = std::make_unique<Box>();
  dot->setFill(roleColor(ColorRole::Primary));
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

  m_glyph->setGlyphSize(Style::fontSizeBody * m_contentScale);
  m_glyph->setColor(widgetForegroundOr(roleColor(ColorRole::OnSurface)));
  m_glyph->measure(renderer);
  m_glyph->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_glyph->width(), m_glyph->height());

  if (m_dot != nullptr) {
    const float dotSize = kDotBaseSize * m_contentScale;
    m_dot->setPosition(m_glyph->width() - dotSize, 0.0f);
  }
}

void NotificationWidget::doUpdate(Renderer& /*renderer*/) {
  refreshIndicatorState();
}

void NotificationWidget::refreshIndicatorState() {
  const bool hasNotifications = (m_manager != nullptr) && !m_manager->all().empty();
  if (hasNotifications == m_hasNotifications) {
    return;
  }
  m_hasNotifications = hasNotifications;
  if (m_dot != nullptr) {
    m_dot->setVisible(m_hasNotifications);
  }
}
