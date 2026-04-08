#pragma once

#include "shell/panel/panel.h"

class Flex;
class Button;
class Input;
class RadioButton;
class Select;
class Label;
class Slider;
class Spinner;
class Toggle;

class TestPanel : public Panel {
public:
  void create(Renderer& renderer) override;
  void layout(Renderer& renderer, float width, float height) override;
  void update(Renderer& renderer) override;

  [[nodiscard]] float preferredWidth() const override { return scaled(640.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(480.0f); }

private:
  Flex* m_container = nullptr;
  Label* m_headerLabel = nullptr;
  Label* m_sliderValueLabel = nullptr;
  Button* m_button = nullptr;
  Select* m_select = nullptr;
  Button* m_glyphButton = nullptr;
  Slider* m_slider = nullptr;
  Toggle* m_toggle = nullptr;
  RadioButton* m_radioA = nullptr;
  RadioButton* m_radioB = nullptr;
  Spinner* m_spinner = nullptr;
  Input* m_input = nullptr;
  Label* m_inputValueLabel = nullptr;
};
