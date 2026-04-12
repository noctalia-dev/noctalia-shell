#pragma once

#include "shell/control_center/tab.h"

#include <limits>

class Button;
class Label;

class CalendarTab : public Tab {
public:
  std::unique_ptr<Flex> create() override;
  void onClose() override;

private:
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void rebuild();

  Flex* m_rootLayout = nullptr;
  Flex* m_card = nullptr;
  Flex* m_header = nullptr;
  Flex* m_previousSlot = nullptr;
  Flex* m_nextSlot = nullptr;
  Flex* m_monthWrap = nullptr;
  Label* m_monthLabel = nullptr;
  Button* m_previousButton = nullptr;
  Button* m_nextButton = nullptr;
  Flex* m_grid = nullptr;
  int m_monthOffset = 0;
  float m_lastInnerWidth = -1.0f;
  float m_lastInnerHeight = -1.0f;
  int m_lastDisplayYear = std::numeric_limits<int>::min();
  int m_lastDisplayMonth = -1;
  int m_lastCurrentYear = std::numeric_limits<int>::min();
  int m_lastCurrentMonth = -1;
  int m_lastToday = -1;
};
