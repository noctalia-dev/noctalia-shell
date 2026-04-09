#pragma once

#include "render/core/color.h"
#include "render/core/mat3.h"
#include "render/programs/color_glyph_program.h"
#include "render/programs/msdf_text_program.h"

#include <cairo.h>
#include <cairo-ft.h>

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_COLOR_H
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
            const Color& color, const Mat3& transform = Mat3::identity());

  // Direct codepoint rendering — bypasses HarfBuzz shaping.
  // Use for icon fonts where codepoints may collide with Unicode control ranges.
  [[nodiscard]] TextMetrics measureGlyph(char32_t codepoint, float fontSize);
  void drawGlyph(float surfaceWidth, float surfaceHeight, float x, float baselineY, char32_t codepoint, float fontSize,
                 const Color& color, const Mat3& transform = Mat3::identity());

  void cleanup();

private:
  struct FontSlot {
    FT_Face face = nullptr;
    hb_font_t* hbFont = nullptr;
    msdfgen::FontHandle* fontHandle = nullptr;
    cairo_font_face_t* cairoFace = nullptr; // non-null for COLR v1 fonts
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
    bool isColor = false; // true → atlasPage indexes m_colorAtlasPages (RGBA)
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
  GLuint ensureColorAtlasPage(std::uint32_t page);
  void prepareAtlasUploadState() const;
  void setShapingSize(float fontSize);
  std::vector<ShapedGlyph> shapeWithFallback(std::string_view text, float fontSize);
  void shapeRunWithSlot(std::string_view run, std::uint32_t slotIndex, std::vector<ShapedGlyph>& out);
  void shapeRunWithFallback(std::string_view run, std::vector<ShapedGlyph>& out);

  FT_Library m_library = nullptr;
  std::vector<FontSlot> m_fontSlots;
  MsdfTextProgram m_program;
  ColorGlyphProgram m_colorProgram;
  std::vector<GLuint> m_atlasPages;
  std::vector<GLuint> m_colorAtlasPages;
  int m_atlasWidth = 512;
  int m_atlasHeight = 512;
  int m_atlasCursorX = 1;
  int m_atlasCursorY = 1;
  int m_atlasRowHeight = 0;
  int m_colorAtlasCursorX = 1;
  int m_colorAtlasCursorY = 1;
  int m_colorAtlasRowHeight = 0;
  float m_currentShapingSize = 0.0f;
  std::uint32_t m_emojiSlotIndex = UINT32_MAX; // slot index of the color emoji font, UINT32_MAX if none
  std::unordered_map<GlyphKey, Glyph> m_glyphs;
};
