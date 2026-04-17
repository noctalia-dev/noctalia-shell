#pragma once

#include "render/scene/node.h"
#include "ui/palette.h"

#include <optional>
#include <string_view>

class GlyphNode;
class Renderer;

class Glyph : public Node {
public:
  Glyph();

  void setGlyph(std::string_view name);
  void setCodepoint(char32_t codepoint);
  void setGlyphSize(float size);
  void setColor(const ThemeColor& color);
  // Explicit fixed color.
  void setColor(const Color& color);

  void measure(Renderer& renderer);

  [[nodiscard]] float baselineOffset() const noexcept { return m_baselineOffset; }

private:
  void doLayout(Renderer& renderer) override;
  void applyPalette();

  GlyphNode* m_glyphNode = nullptr;
  float m_baselineOffset = 0.0f;
  float m_logicalFontSize = 0.0f;
  ThemeColor m_color = roleColor(ColorRole::OnSurface);
  Signal<>::ScopedConnection m_paletteConn;

  // Memoized measure() inputs — lets repeated layout passes with identical
  // glyph + size skip the Pango/fontconfig path entirely.
  char32_t m_cachedCodepoint = 0;
  float m_cachedFontSize = 0.0f;
  float m_cachedLogicalFontSize = 0.0f;
  float m_cachedAssignedWidth = -1.0f;
  float m_cachedFlexGrow = 0.0f;
  bool m_measureCached = false;
};
