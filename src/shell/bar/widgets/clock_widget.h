#pragma once

#include "shell/bar/widget.h"

#include <cstdint>
#include <string>

class Label;
struct wl_output;

class ClockWidget : public Widget {
public:
  ClockWidget(wl_output* output, std::string format = "{:%H:%M}", std::string verticalFormat = "");

  void create() override;

private:
  [[nodiscard]] std::string formatTimeText() const;
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  wl_output* m_output = nullptr;
  std::string m_format;
  std::string m_verticalFormat;
  bool m_isVertical = false;
  Label* m_label = nullptr;
  std::string m_lastText;
};
