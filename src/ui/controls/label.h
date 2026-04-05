#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <string>
#include <string_view>

class Renderer;
class TextNode;

class Label : public Node {
public:
  Label();

  void setText(std::string_view text);
  void setFontSize(float size);
  void setColor(const Color& color);
  void setMinWidth(float minWidth);
  void setMaxWidth(float maxWidth);
  void setBold(bool bold);

  [[nodiscard]] const std::string& text() const noexcept;
  [[nodiscard]] float fontSize() const noexcept;
  [[nodiscard]] const Color& color() const noexcept;
  [[nodiscard]] float maxWidth() const noexcept;
  [[nodiscard]] bool bold() const noexcept;
  [[nodiscard]] float baselineOffset() const noexcept { return m_baselineOffset; }

  void measure(Renderer& renderer);

  void setCaptionStyle();

private:
  TextNode* m_textNode = nullptr;
  float m_minWidth = 0.0f;
  float m_baselineOffset = 0.0f;
};
