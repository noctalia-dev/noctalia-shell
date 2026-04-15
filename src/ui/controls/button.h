#pragma once

#include "ui/controls/flex.h"

#include "render/core/color.h"
#include "ui/signal.h"

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
  struct ButtonStateColors {
    ThemeColor bg;
    ThemeColor border;
    ThemeColor label;
  };

  struct ButtonPalette {
    float borderWidth = 0.0f;
    ButtonStateColors normal;
    ButtonStateColors hover;
    ButtonStateColors pressed;
  };

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
  void setOnEnter(std::function<void()> callback);
  void setOnLeave(std::function<void()> callback);
  void setHoverSuppressed(bool suppressed);
  void setCursorShape(std::uint32_t shape);

  // Call after layout() to sync InputArea bounds
  void updateInputArea();

  [[nodiscard]] Label* label() const noexcept { return m_label; }
  [[nodiscard]] Glyph* glyph() const noexcept { return m_glyph; }
  [[nodiscard]] bool hovered() const noexcept;
  [[nodiscard]] bool pressed() const noexcept;
  [[nodiscard]] bool enabled() const noexcept { return m_enabled; }

private:
  void refreshInputAreaEnabled();
  void ensureLabel();
  void ensureGlyph();
  void applyVariant();
  void applyVisualState();
  void resolveVisualStateColors(Color& bg, Color& border, Color& label) const;
  void doLayout(Renderer& renderer) override;

  void applyColors(const Color& bg, const Color& border, const Color& label);

  Glyph* m_glyph = nullptr;
  Label* m_label = nullptr;
  InputArea* m_inputArea = nullptr;
  std::uint32_t m_animId = 0;
  std::function<void()> m_onClick;
  std::function<void()> m_onMotion;
  std::function<void()> m_onEnter;
  std::function<void()> m_onLeave;
  ButtonVariant m_variant = ButtonVariant::Default;
  ButtonPalette m_palette;
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
  bool m_visualStateInitialized = false;
  Signal<>::ScopedConnection m_paletteConn;
};
