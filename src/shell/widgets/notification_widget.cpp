#include "shell/widgets/notification_widget.h"

#include "notification/notification_manager.h"
#include "render/scene/input_area.h"
#include "render/scene/node.h"
#include "shell/panel/panel_manager.h"
#include "ui/controls/box.h"
#include "ui/controls/icon.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <memory>

NotificationWidget::NotificationWidget(NotificationManager* manager, wl_output* output, std::int32_t scale)
    : m_manager(manager), m_output(output), m_scale(scale) {}

void NotificationWidget::create(Renderer& renderer) {
  auto area = std::make_unique<InputArea>();
  area->setOnClick([this](const InputArea::PointerData& /*data*/) {
    float absX = 0.0f;
    float absY = 0.0f;
    // auto* node = root();
    // if (node != nullptr) {
    //   Node::absolutePosition(node, absX, absY);
    //   absX += node->width() * 0.5f;
    //   absY += node->height() * 0.5f;
    // }
    PanelManager::instance().togglePanel("control-center", m_output, m_scale, absX, absY, "notifications");
  });

  auto icon = std::make_unique<Icon>();
  icon->setIcon("bell");
  icon->setIconSize(Style::fontSizeBody * m_contentScale);
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  area->addChild(std::move(icon));

  auto dot = std::make_unique<Box>();
  dot->setFill(palette.primary);
  dot->setRadius(Style::radiusFull);
  dot->setVisible(false);
  m_dot = area->addChild(std::move(dot));

  m_root = std::move(area);
  refreshIndicatorState();
  layout(renderer, 0.0f, 0.0f);
}

void NotificationWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  auto* rootNode = root();
  if (m_icon == nullptr || rootNode == nullptr) {
    return;
  }

  m_icon->measure(renderer);
  m_icon->setPosition(0.0f, 0.0f);
  rootNode->setSize(m_icon->width(), m_icon->height());

  if (m_dot != nullptr && m_dot->visible()) {
    const float kDotSize = 5.0f * m_contentScale;
    const float dotX = std::max(0.0f, m_icon->width() - kDotSize + 1.0f);
    const float dotY = -1.0f;
    m_dot->setPosition(dotX, dotY);
    m_dot->setSize(kDotSize, kDotSize);
  }
}

void NotificationWidget::update(Renderer& renderer) {
  refreshIndicatorState();
  Widget::update(renderer);
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
