#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

class GlyphNode : public Node {
public:
  GlyphNode() : Node(NodeType::Glyph) {}

  [[nodiscard]] char32_t codepoint() const noexcept { return m_codepoint; }
  [[nodiscard]] float fontSize() const noexcept { return m_fontSize; }
  [[nodiscard]] const Color& color() const noexcept { return m_color; }

  void setCodepoint(char32_t codepoint) {
    if (m_codepoint == codepoint) {
      return;
    }
    m_codepoint = codepoint;
    markDirty();
  }

  void setFontSize(float size) {
    if (m_fontSize == size) {
      return;
    }
    m_fontSize = size;
    markDirty();
  }

  void setColor(const Color& color) {
    m_color = color;
    markDirty();
  }

private:
  char32_t m_codepoint = 0;
  float m_fontSize = 16.0f;
  Color m_color;
};
