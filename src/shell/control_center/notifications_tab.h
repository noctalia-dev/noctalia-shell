#pragma once

#include "shell/control_center/tab.h"
#include "system/icon_resolver.h"

#include <cstdint>
#include <unordered_set>

class NotificationManager;
class Button;
class ScrollView;
class Segmented;

class NotificationsTab : public Tab {
public:
  explicit NotificationsTab(NotificationManager* notifications);

  std::unique_ptr<Flex> create() override;
  std::unique_ptr<Flex> createHeaderActions() override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;
  void clearAllNotifications();
  void removeNotificationEntry(uint32_t id, bool wasActive);
  void toggleNotificationExpanded(uint32_t id);
  void rebuild(Renderer& renderer, float width);

  NotificationManager* m_notifications = nullptr;
  IconResolver m_iconResolver;
  Flex* m_root = nullptr;
  ScrollView* m_scroll = nullptr;
  Flex* m_list = nullptr;
  Button* m_clearAllButton = nullptr;
  Segmented* m_filter = nullptr;
  std::size_t m_filterIndex = 0;
  std::unordered_set<uint32_t> m_expandedIds;
  std::uint64_t m_lastSerial = 0;
  std::uint64_t m_lastVisualSignature = 0;
  float m_lastWidth = -1.0f;
  /// Wall-clock coarse slot so relative times (e.g. "2 min ago") refresh without churning every frame.
  std::int64_t m_lastRelativeTimeSlot = -1;
  std::size_t m_lastRebuildFilterIndex = static_cast<std::size_t>(-1);
};
