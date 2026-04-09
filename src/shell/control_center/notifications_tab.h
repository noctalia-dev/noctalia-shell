#pragma once

#include "shell/control_center/tab.h"

#include <cstdint>

class NotificationManager;
class ScrollView;

class NotificationsTab : public Tab {
public:
  explicit NotificationsTab(NotificationManager* notifications);

  std::unique_ptr<Flex> create() override;
  void layout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void update(Renderer& renderer) override;
  void onClose() override;

private:
  void rebuild(Renderer& renderer, float width);

  NotificationManager* m_notifications = nullptr;
  ScrollView* m_scroll = nullptr;
  Flex* m_list = nullptr;
  std::uint64_t m_lastSerial = 0;
  float m_lastWidth = -1.0f;
};
