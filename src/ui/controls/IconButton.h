#pragma once

#include "ui/controls/Box.h"
#include "ui/controls/Button.h"

#include "render/core/Color.h"

#include <functional>
#include <string_view>

class Icon;
class InputArea;
class Label;

class IconButton : public Box {
public:
  IconButton();

  void setText(std::string_view text);
  void setIcon(std::string_view name);
  void setFontSize(float size);
  void setIconSize(float size);
  void setVariant(ButtonVariant variant);
  void setOnClick(std::function<void()> callback);
  void setCursorShape(std::uint32_t shape);
  void layout(Renderer& renderer) override;

  [[nodiscard]] Label* label() const noexcept { return m_label; }
  [[nodiscard]] Icon* icon() const noexcept { return m_icon; }
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;

private:
  void applyVariant();
  void applyVisualState();

  Icon* m_icon = nullptr;
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
