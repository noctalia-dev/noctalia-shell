#pragma once

#include "ui/controls/flex.h"

#include <cstddef>
#include <functional>
#include <string_view>
#include <vector>

class Button;

class Segmented : public Flex {
public:
  Segmented();

  std::size_t addOption(std::string_view label);
  std::size_t addOption(std::string_view label, std::string_view glyph);

  void setSelectedIndex(std::size_t index);
  [[nodiscard]] std::size_t selectedIndex() const noexcept { return m_selected; }

  void setFontSize(float size);
  void setScale(float scale);

  void setOnChange(std::function<void(std::size_t)> callback);

private:
  Button* makeSegmentButton(std::string_view label, std::string_view glyph, std::size_t index);
  void refreshVariants();
  void applyOuterStyle();
  [[nodiscard]] float effectiveFontSize() const noexcept;

  std::vector<Button*> m_buttons;
  std::size_t m_selected = 0;
  std::function<void(std::size_t)> m_onChange;
  float m_fontSize = 0.0f;
  float m_scale = 1.0f;
};
