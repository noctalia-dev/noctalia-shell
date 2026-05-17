#pragma once

#include "dbus/upower/upower_service.h"
#include "shell/bar/widget.h"
#include "ui/palette.h"

#include <string>

class Glyph;
class Label;

class BatteryWidget : public Widget {
public:
  BatteryWidget(UPowerService* upower, std::string deviceSelector = "auto", int warningThreshold = 0,
                ColorSpec warningColor = {});

  void create() override;

private:
  void doLayout(Renderer& renderer, float containerWidth, float containerHeight) override;
  void doUpdate(Renderer& renderer) override;
  void syncState(Renderer& renderer);

  UPowerService* m_upower = nullptr;
  std::string m_deviceSelector = "auto";
  int m_warningThreshold = 0;
  ColorSpec m_warningColor;
  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  double m_lastPct = -1.0;
  BatteryState m_lastState = BatteryState::Unknown;
  bool m_lastPresent = false;
  bool m_isVertical = false;
  bool m_lastVertical = false;
};
