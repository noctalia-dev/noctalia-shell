#pragma once

#include "shell/Widget.h"

class Icon;
class NotificationManager;
class RectNode;

class NotificationWidget : public Widget {
public:
  explicit NotificationWidget(NotificationManager* manager);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void refreshIndicatorState();

  NotificationManager* m_manager = nullptr;
  Icon* m_icon = nullptr;
  RectNode* m_dot = nullptr;
  bool m_hasNotifications = false;
};
