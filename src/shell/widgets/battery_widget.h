#pragma once

#include "dbus/upower/upower_service.h"
#include "shell/widget/widget.h"

class Glyph;
class Label;

class BatteryWidget : public Widget {
public:
  explicit BatteryWidget(UPowerService* upower);

  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void update(Renderer& renderer) override;

private:
  void syncState(Renderer& renderer);

  UPowerService* m_upower = nullptr;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  double m_lastPct = -1.0;
  BatteryState m_lastState = BatteryState::Unknown;
  bool m_lastPresent = false;
};
