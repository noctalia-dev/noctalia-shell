#pragma once

#include "shell/panel/panel.h"

#include <cstdint>

class Button;
class Flex;
class Label;
class NotificationManager;
class ScrollView;
class Renderer;

class NotificationHistoryPanel : public Panel {
public:
  explicit NotificationHistoryPanel(NotificationManager* manager);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float width, float height) override;
  void update(Renderer& renderer) override;

  [[nodiscard]] float preferredWidth() const override { return 420.0f; }
  [[nodiscard]] float preferredHeight() const override { return 460.0f; }

private:
  void rebuildList(Renderer& renderer, float width);
  void dismissEntry(uint32_t id, bool wasActive);
  void clearAll();

  NotificationManager* m_manager = nullptr;
  Flex* m_container = nullptr;
  Flex* m_header = nullptr;
  Flex* m_headerRow = nullptr;
  Label* m_titleLabel = nullptr;
  Label* m_subtitleLabel = nullptr;
  Button* m_clearAllButton = nullptr;
  ScrollView* m_scrollView = nullptr;
  Flex* m_list = nullptr;
  std::uint64_t m_lastChangeSerial = 0;
  float m_lastWidth = 0.0f;
  float m_lastHeight = 0.0f;
  float m_lastListWidth = -1.0f;
};
