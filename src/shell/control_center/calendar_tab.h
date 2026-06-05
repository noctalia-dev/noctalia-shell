#pragma once

#include "shell/control_center/tab.h"

#include <limits>

class Button;
class CalendarService;
class ConfigService;
class InputArea;
class Label;
class ScrollView;

class CalendarTab : public Tab {
public:
  explicit CalendarTab(ConfigService* config = nullptr, CalendarService* calendar = nullptr);

  std::unique_ptr<Flex> create() override;
  void setActive(bool active) override;
  void onClose() override;

private:
  void resetToCurrentMonth();
  void doLayout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void doUpdate(Renderer& renderer) override;
  void rebuild();
  void rebuildEventList(float scale);

  ConfigService* m_config = nullptr;
  CalendarService* m_calendar = nullptr;
  bool m_changeCallbackRegistered = false;
  bool m_eventsDirty = false;
  Flex* m_rootLayout = nullptr;
  InputArea* m_calendarArea = nullptr;
  Flex* m_card = nullptr;
  Flex* m_header = nullptr;
  Flex* m_previousSlot = nullptr;
  Flex* m_nextSlot = nullptr;
  Flex* m_monthWrap = nullptr;
  Label* m_monthLabel = nullptr;
  Label* m_monthSubLabel = nullptr;
  Button* m_previousButton = nullptr;
  Button* m_nextButton = nullptr;
  Flex* m_grid = nullptr;
  Flex* m_eventsCard = nullptr;
  Label* m_eventsTitle = nullptr;
  ScrollView* m_eventsScroll = nullptr;
  int m_selectedYear = std::numeric_limits<int>::min();
  int m_selectedMonth = -1;
  int m_selectedDay = -1;
  int m_monthOffset = 0;
  float m_scrollAccum = 0.0f;
  float m_lastInnerWidth = -1.0f;
  float m_lastInnerHeight = -1.0f;
  int m_lastDisplayYear = std::numeric_limits<int>::min();
  int m_lastDisplayMonth = -1;
  int m_lastCurrentYear = std::numeric_limits<int>::min();
  int m_lastCurrentMonth = -1;
  int m_lastToday = -1;
};
