#include "shell/widgets/NotificationWidget.h"

#include "notification/NotificationManager.h"
#include "render/programs/RoundedRectProgram.h"
#include "render/scene/RectNode.h"
#include "ui/controls/Icon.h"
#include "ui/style/Palette.h"
#include "ui/style/Style.h"

#include <algorithm>
#include <memory>

NotificationWidget::NotificationWidget(NotificationManager* manager) : m_manager(manager) {}

void NotificationWidget::create(Renderer& renderer) {
  auto root = std::make_unique<Node>();

  auto icon = std::make_unique<Icon>();
  icon->setIcon("bell");
  icon->setColor(palette.onSurface);
  m_icon = icon.get();
  root->addChild(std::move(icon));

  auto dot = std::make_unique<RectNode>();
  auto dotStyle = dot->style();
  dotStyle.fill = palette.primary;
  dotStyle.border = palette.primary;
  dotStyle.fillMode = FillMode::Solid;
  dotStyle.radius = 3.0f;
  dotStyle.softness = 1.0f;
  dotStyle.borderWidth = 0.0f;
  dot->setStyle(dotStyle);
  dot->setVisible(false);
  m_dot = static_cast<RectNode*>(root->addChild(std::move(dot)));

  m_root = std::move(root);
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
    constexpr float kDotSize = 5.0f;
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
