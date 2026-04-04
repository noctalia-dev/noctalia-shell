#pragma once

#include "shell/Widget.h"

class Icon;

class NotificationWidget : public Widget {
public:
  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;

private:
  Icon* m_icon = nullptr;
};
