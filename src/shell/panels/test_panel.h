#pragma once

#include "shell/panel/panel.h"

class Box;
class Button;
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

  [[nodiscard]] float preferredWidth() const override { return 640.0f; }
  [[nodiscard]] float preferredHeight() const override { return 480.0f; }

private:
  Box* m_container = nullptr;
  Label* m_headerLabel = nullptr;
  Label* m_sliderValueLabel = nullptr;
  Button* m_button = nullptr;
  Select* m_select = nullptr;
  Button* m_iconButton = nullptr;
  Slider* m_slider = nullptr;
  Toggle* m_toggle = nullptr;
  Spinner* m_spinner = nullptr;
};
