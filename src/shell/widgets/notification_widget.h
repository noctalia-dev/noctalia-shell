#pragma once

#include "shell/widget/widget.h"

struct wl_output;
class Glyph;
class Node;
class NotificationManager;

class NotificationWidget : public Widget {
public:
  NotificationWidget(NotificationManager* manager, wl_output* output);

  void create() override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void refreshIndicatorState();

  NotificationManager* m_manager = nullptr;
  wl_output* m_output = nullptr;
  Glyph* m_glyph = nullptr;
  Node* m_dot = nullptr;
  bool m_hasNotifications = false;
};
