#pragma once

#include "ui/controls/flex.h"

#include "render/core/color.h"

#include <functional>
#include <string_view>

class AnimationManager;

class Glyph;
class InputArea;
class Label;

enum class ButtonContentAlign : std::uint8_t {
  Center,
  Start,
  End,
};

enum class ButtonVariant : std::uint8_t {
  Default,
  Secondary,
  Destructive,
  Outline,
  Ghost,
  Accent,
  Tab,
  TabActive,
};

class Button : public Flex {
public:
  Button();
  ~Button() override;

  void setText(std::string_view text);
  void setGlyph(std::string_view name);
  void setFontSize(float size);
  void setGlyphSize(float size);
  void setEnabled(bool enabled);
  void setSelected(bool selected);
  void setContentAlign(ButtonContentAlign align);
  void setVariant(ButtonVariant variant);
  void setOnClick(std::function<void()> callback);
  void setOnMotion(std::function<void()> callback);
  void setHoverSuppressed(bool suppressed);
  void setCursorShape(std::uint32_t shape);
  void layout(Renderer& renderer) override;

  // Call after layout() to sync InputArea bounds
  void updateInputArea();

  [[nodiscard]] Label* label() const noexcept { return m_label; }
  [[nodiscard]] Glyph* glyph() const noexcept { return m_glyph; }
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }

private:
  void ensureLabel();
  void ensureGlyph();
  void applyVariant();
  void applyVisualState();

  void applyColors(const Color& bg, const Color& border, const Color& label);

  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  InputArea* m_inputArea = nullptr;
  std::uint32_t m_animId = 0;
  std::function<void()> m_onClick;
  std::function<void()> m_onMotion;
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
  // Animation: snapshot of colors at transition start
  Color m_fromBg{};
  Color m_fromBorder{};
  Color m_fromLabel{};
  Color m_targetBg{};
  Color m_targetBorder{};
  Color m_targetLabel{};
  ButtonContentAlign m_contentAlign = ButtonContentAlign::Center;
  bool m_enabled = true;
  bool m_selected = false;
  bool m_hoverSuppressed = false;
};
