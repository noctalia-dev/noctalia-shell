#pragma once

#include "shell/panel/panel.h"

#include <string_view>

class ColorPickerSheet;

// Thin Panel adapter for the layer-shell "color-picker" id: delegates chrome to
// `ColorPickerSheet` (controls layer) and wires `PanelManager` + optional `#RRGGBB` context.
class ColorPickerPanel : public Panel {
public:
  void create() override;
  void onOpen(std::string_view context) override;
  void onClose() override;

  [[nodiscard]] float preferredWidth() const override;
  [[nodiscard]] float preferredHeight() const override;

private:
  void doLayout(Renderer& renderer, float width, float height) override;

  ColorPickerSheet* m_sheet = nullptr;
};
