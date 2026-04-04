#include "shell/widgets/NotificationWidget.h"

#include "ui/controls/Icon.h"

void NotificationWidget::create(Renderer& renderer) {
  auto icon = std::make_unique<Icon>();
  icon->setIcon("bell");
  m_icon = icon.get();
  m_root = std::move(icon);
  m_icon->measure(renderer);
}

void NotificationWidget::layout(Renderer& renderer, float /*containerWidth*/, float /*containerHeight*/) {
  m_icon->measure(renderer);
}
