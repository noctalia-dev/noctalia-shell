#pragma once

#include "shell/desktop/desktop_widget.h"
#include "ui/palette.h"

#include <cstdint>
#include <string>

class Label;
class Node;
class RectNode;

class DesktopClockWidget : public DesktopWidget {
public:
  enum class Style : std::uint8_t {
    Digital,
    Analog,
  };

  DesktopClockWidget(Style style, std::string format, ColorSpec color, bool shadow, bool circle);

  void create() override;
  [[nodiscard]] bool wantsSecondTicks() const override;
  bool applySetting(
      const std::string& key, const WidgetSettingValue& value,
      const std::unordered_map<std::string, WidgetSettingValue>& allSettings, Renderer& renderer
  ) override;

private:
  [[nodiscard]] std::string formatText() const;
  void doLayout(Renderer& renderer) override;
  void doUpdate(Renderer& renderer) override;
  void onFontFamilyChanged(const std::string& family, Renderer& renderer) override;
  void applyShadow();
  void syncStyleVisibility();
  void syncCircleVisibility();
  void syncAnalogColors();
  void layoutAnalog(Renderer& renderer, float size);
  void layoutDigital(Renderer& renderer);
  void updateAnalogHands();
  [[nodiscard]] static Style styleFromSetting(std::string_view value);

  Style m_style;
  std::string m_format;
  ColorSpec m_color;
  bool m_shadow;
  bool m_showCircle;
  bool m_showsSeconds = false;
  Label* m_label = nullptr;
  Node* m_digitalRoot = nullptr;
  Node* m_analogRoot = nullptr;
  Node* m_ticksRoot = nullptr;
  Node* m_hourPivot = nullptr;
  Node* m_minutePivot = nullptr;
  Node* m_secondPivot = nullptr;
  RectNode* m_face = nullptr;
  RectNode* m_hub = nullptr;
  std::string m_lastText;
  int m_lastHour = -1;
  int m_lastMinute = -1;
  int m_lastSecond = -1;
};
