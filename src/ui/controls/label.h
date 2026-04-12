#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"

#include <optional>
#include <string>
#include <string_view>

class Renderer;
class TextNode;

class Label : public Node {
public:
  Label();

  void setText(std::string_view text);
  void setFontSize(float size);
  void setColor(const ThemeColor& color);
  // Explicit fixed color.
  void setColor(const Color& color);
  void setMinWidth(float minWidth);
  void setMaxWidth(float maxWidth);
  void setMaxLines(int maxLines);
  void setBold(bool bold);

  [[nodiscard]] const std::string& text() const noexcept;
  [[nodiscard]] float fontSize() const noexcept;
  [[nodiscard]] const Color& color() const noexcept;
  [[nodiscard]] float maxWidth() const noexcept;
  [[nodiscard]] bool bold() const noexcept;
  [[nodiscard]] float baselineOffset() const noexcept { return m_baselineOffset; }

  void layout(Renderer& renderer) override;
  void measure(Renderer& renderer);

  void setCaptionStyle();

private:
  void applyPalette();

  TextNode* m_textNode = nullptr;
  float m_minWidth = 0.0f;
  float m_baselineOffset = 0.0f;
  ThemeColor m_color = roleColor(ColorRole::OnSurface);
  Signal<>::ScopedConnection m_paletteConn;
};
