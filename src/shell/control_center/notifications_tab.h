#pragma once

#include "shell/control_center/tab.h"

#include <cstdint>
#include <unordered_set>

class NotificationManager;
class Button;
class ScrollView;

class NotificationsTab : public Tab {
public:
  explicit NotificationsTab(NotificationManager* notifications);

  std::unique_ptr<Flex> create() override;
  std::unique_ptr<Flex> createHeaderActions() override;
  void layout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void update(Renderer& renderer) override;
  void onClose() override;

private:
  void clearAllNotifications();
  void removeNotificationEntry(uint32_t id, bool wasActive);
  void toggleNotificationExpanded(uint32_t id);
  void rebuild(Renderer& renderer, float width);

  NotificationManager* m_notifications = nullptr;
  Flex* m_root = nullptr;
  ScrollView* m_scroll = nullptr;
  Flex* m_list = nullptr;
  Button* m_clearAllButton = nullptr;
  std::unordered_set<uint32_t> m_expandedIds;
  std::uint64_t m_lastSerial = 0;
  float m_lastWidth = -1.0f;
};
