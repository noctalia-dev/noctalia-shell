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

  Flex* m_container = nullptr;
  Flex* m_card = nullptr;
  Label* m_monthLabel = nullptr;
  Flex* m_grid = nullptr;
  int m_monthOffset = 0;
};
