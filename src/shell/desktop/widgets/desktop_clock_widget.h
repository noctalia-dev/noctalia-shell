#pragma once

#include "shell/desktop/desktop_widget.h"
#include "ui/palette.h"

#include <string>

class Label;

class DesktopClockWidget : public DesktopWidget {
public:
  DesktopClockWidget(std::string format, ThemeColor color, bool shadow);

  void create() override;
  [[nodiscard]] bool wantsSecondTicks() const override;

private:
  [[nodiscard]] std::string formatText() const;
  void doLayout(Renderer& renderer) override;
  void doUpdate(Renderer& renderer) override;
  void applyShadow();

  std::string m_format;
  ThemeColor m_color;
  bool m_shadow;
  bool m_showsSeconds = false;
  Label* m_label = nullptr;
  std::string m_lastText;
};
