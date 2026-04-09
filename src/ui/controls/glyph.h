#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <string_view>

class GlyphNode;
class Renderer;

class Glyph : public Node {
public:
  Glyph();

  void setGlyph(std::string_view name);
  void setCodepoint(char32_t codepoint);
  void setGlyphSize(float size);
  void setColor(const Color& color);

  void layout(Renderer& renderer) override;
  void measure(Renderer& renderer);

  [[nodiscard]] float baselineOffset() const noexcept { return m_baselineOffset; }

private:
  GlyphNode* m_glyphNode = nullptr;
  float m_baselineOffset = 0.0f;
  float m_logicalFontSize = 0.0f;
};
