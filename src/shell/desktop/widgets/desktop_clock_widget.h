#pragma once

#include "shell/desktop/desktop_widget.h"

#include <string>

class Label;
class TimeService;

class DesktopClockWidget : public DesktopWidget {
public:
  DesktopClockWidget(const TimeService& timeService, std::string format = "{:%H:%M}");

  void create() override;
  [[nodiscard]] bool wantsSecondTicks() const override;

private:
  [[nodiscard]] std::string formatText() const;
  void doLayout(Renderer& renderer) override;
  void doUpdate(Renderer& renderer) override;

  const TimeService& m_timeService;
  std::string m_format;
  bool m_showsSeconds = false;
  Label* m_label = nullptr;
  std::string m_lastText;
};
