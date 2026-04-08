#pragma once

#include "render/core/color.h"
#include "render/programs/msdf_text_program.h"

#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb-ft.h>

#include <cstdint>
#include <string_view>
#include <unordered_map>
#include <vector>

struct ResolvedFont;

namespace msdfgen {
class FontHandle;
}

class MsdfTextRenderer {
public:
  struct TextMetrics {
    float width = 0.0f;
    float left = 0.0f;
    float right = 0.0f;
    float top = 0.0f;
    float bottom = 0.0f;
  };

  MsdfTextRenderer();
  ~MsdfTextRenderer();

  MsdfTextRenderer(const MsdfTextRenderer&) = delete;
  MsdfTextRenderer& operator=(const MsdfTextRenderer&) = delete;

  struct TruncatedText {
    std::string text;
    float width = 0.0f;
  };

  void initialize(const std::vector<ResolvedFont>& fonts);
  [[nodiscard]] TextMetrics measure(std::string_view text, float fontSize);
  [[nodiscard]] TruncatedText truncate(std::string_view text, float fontSize, float maxWidth);
  void draw(float surfaceWidth, float surfaceHeight, float x, float baselineY, std::string_view text, float fontSize,
            const Color& color, float rotation = 0.0f, float renderScale = 1.0f);

  // Direct codepoint rendering — bypasses HarfBuzz shaping.
  // Use for icon fonts where codepoints may collide with Unicode control ranges.
  [[nodiscard]] TextMetrics measureGlyph(char32_t codepoint, float fontSize);
  void drawGlyph(float surfaceWidth, float surfaceHeight, float x, float baselineY, char32_t codepoint, float fontSize,
                 const Color& color, float rotation = 0.0f, float renderScale = 1.0f);

  void cleanup();

private:
  struct FontSlot {
    FT_Face face = nullptr;
    hb_font_t* hbFont = nullptr;
    msdfgen::FontHandle* fontHandle = nullptr;
  };

  struct Glyph {
    float atlasWidth = 0.0f;
    float atlasHeight = 0.0f;
    float bearingX = 0.0f;
    float bearingY = 0.0f;
    float u0 = 0.0f;
    float v0 = 0.0f;
    float u1 = 1.0f;
    float v1 = 1.0f;
    std::uint32_t atlasPage = 0;
  };

  // Cache key: (slotIndex << 24) | glyphIndex
  using GlyphKey = std::uint64_t;
  static GlyphKey makeGlyphKey(std::uint32_t slotIndex, std::uint32_t glyphIndex) {
    return (static_cast<std::uint64_t>(slotIndex) << 32) | glyphIndex;
  }

  struct ShapedGlyph {
    GlyphKey key;
    std::uint32_t slotIndex;
    std::uint32_t glyphIndex;
    hb_glyph_position_t position;
  };

  Glyph& loadGlyph(std::uint32_t slotIndex, std::uint32_t glyphIndex);
  GLuint ensureAtlasPage(std::uint32_t page);
  void prepareAtlasUploadState() const;
  void setShapingSize(float fontSize);
  std::vector<ShapedGlyph> shapeWithFallback(std::string_view text, float fontSize);

  FT_Library m_library = nullptr;
  std::vector<FontSlot> m_fontSlots;
  MsdfTextProgram m_program;
  std::vector<GLuint> m_atlasPages;
  int m_atlasWidth = 512;
  int m_atlasHeight = 512;
  int m_atlasCursorX = 1;
  int m_atlasCursorY = 1;
  int m_atlasRowHeight = 0;
  float m_currentShapingSize = 0.0f;
  std::unordered_map<GlyphKey, Glyph> m_glyphs;
};
