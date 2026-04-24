#pragma once

#include "shell/panel/panel.h"

class Flex;
class Button;
class Box;
class Checkbox;
class Glyph;
class Input;
class RadioButton;
class Select;
class Label;
class Slider;
class Spinner;
class Toggle;

class TestPanel : public Panel {
public:
  void create() override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override { return scaled(950.0f); }
  [[nodiscard]] float preferredHeight() const override { return scaled(900.0f); }
  // [[nodiscard]] bool centeredHorizontally() const override { return true; }
  // [[nodiscard]] bool centeredVertically() const override { return true; }

private:
  void doLayout(Renderer& renderer, float width, float height) override;
  void doUpdate(Renderer& renderer) override;
  Flex* m_container = nullptr;
  Label* m_headerLabel = nullptr;
  Label* m_sliderValueLabel = nullptr;
  Label* m_toggleValueLabel = nullptr;
  Label* m_checkboxValueLabel = nullptr;
  Select* m_select = nullptr;
  Button* m_glyphTextButton = nullptr;
  Button* m_glyphButton = nullptr;
  Box* m_glyphBox = nullptr;
  Glyph* m_glyph = nullptr;
  Box* m_transformStage = nullptr;
  Box* m_transformDemoBox = nullptr;
  Glyph* m_transformDemoGlyph = nullptr;
  Button* m_transformDemoButton = nullptr;
  Box* m_transformBadgeBox = nullptr;
  Label* m_transformBadgeLabel = nullptr;
  Slider* m_slider = nullptr;
  Toggle* m_toggle = nullptr;
  Checkbox* m_checkbox = nullptr;
  RadioButton* m_radioA = nullptr;
  RadioButton* m_radioB = nullptr;
  Spinner* m_spinner = nullptr;
  Input* m_input = nullptr;
  Label* m_inputValueLabel = nullptr;
  Button* m_openFileDialogButton = nullptr;
  Label* m_fileDialogResultLabel = nullptr;
  Label* m_transformHelp = nullptr;
  Box* m_colorPickerResultSwatch = nullptr;
  Button* m_openColorPickerButton = nullptr;
};
