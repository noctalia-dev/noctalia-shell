#pragma once

#include "shell/control_center/tab.h"

class Label;

class CalendarTab : public Tab {
public:
  std::unique_ptr<Flex> build(Renderer& renderer) override;
  void layout(Renderer& renderer, float contentWidth, float bodyHeight) override;
  void onClose() override;

private:
  void rebuild(Renderer& renderer);

  Flex* m_rootLayout = nullptr;
  Flex* m_card = nullptr;
  Flex* m_header = nullptr;
  Flex* m_monthWrap = nullptr;
  Label* m_monthLabel = nullptr;
  Flex* m_grid = nullptr;
  int m_monthOffset = 0;
};
