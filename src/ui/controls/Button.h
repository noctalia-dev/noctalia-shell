#pragma once

#include "ui/controls/Box.h"

#include <functional>
#include <string_view>

class InputArea;
class Label;

enum class ButtonVariant : std::uint8_t {
  Default,
  Secondary,
  Destructive,
  Outline,
  Ghost,
};

class Button : public Box {
public:
  Button();

  void setText(std::string_view text);
  void setFontSize(float size);
  void setVariant(ButtonVariant variant);
  void setOnClick(std::function<void()> callback);
  void setCursorShape(std::uint32_t shape);

  // Call after layout() to sync InputArea bounds
  void updateInputArea();

  [[nodiscard]] Label* label() const noexcept { return m_label; }
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;

private:
  void applyVariant();

  Label* m_label = nullptr;
  InputArea* m_inputArea = nullptr;
  std::function<void()> m_onClick;
  ButtonVariant m_variant = ButtonVariant::Default;
};
