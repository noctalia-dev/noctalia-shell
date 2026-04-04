#pragma once

#include "ui/controls/Box.h"

#include "render/core/Color.h"

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
  void layout(Renderer& renderer) override;

  // Call after layout() to sync InputArea bounds
  void updateInputArea();

  [[nodiscard]] Label* label() const noexcept { return m_label; }
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;

private:
  void applyVariant();
  void applyVisualState();

  Label* m_label = nullptr;
  InputArea* m_inputArea = nullptr;
  std::function<void()> m_onClick;
  ButtonVariant m_variant = ButtonVariant::Default;
  Color m_bgColorNormal{};
  Color m_bgColorHover{};
  Color m_bgColorPressed{};
  Color m_borderColorNormal{};
  Color m_borderColorHover{};
  Color m_borderColorPressed{};
  Color m_labelColorNormal{};
  Color m_labelColorHover{};
  Color m_labelColorPressed{};
};
