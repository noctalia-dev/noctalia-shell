#pragma once

#include "render/Color.hpp"
#include "render/MsdfTextProgram.hpp"

#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb-ft.h>

#include <cstdint>
#include <string_view>
#include <unordered_map>

namespace msdfgen {
class FontHandle;
}

class MsdfTextRenderer {
public:
    struct TextMetrics {
        float width = 0.0f;
        float top = 0.0f;
        float bottom = 0.0f;
    };

    MsdfTextRenderer();
    ~MsdfTextRenderer();

    MsdfTextRenderer(const MsdfTextRenderer&) = delete;
    MsdfTextRenderer& operator=(const MsdfTextRenderer&) = delete;

    void initialize();
    [[nodiscard]] TextMetrics measure(std::string_view text, float fontSize);
    void draw(float surfaceWidth,
              float surfaceHeight,
              float x,
              float baselineY,
              std::string_view text,
              float fontSize,
              const Color& color);
    void cleanup();

private:
    struct Glyph {
        float atlasWidth = 0.0f;
        float atlasHeight = 0.0f;
        float bearingX = 0.0f;
        float bearingY = 0.0f;
        float u0 = 0.0f;
        float v0 = 0.0f;
        float u1 = 1.0f;
        float v1 = 1.0f;
    };

    Glyph& loadGlyph(std::uint32_t glyphIndex);
    void ensureAtlasInitialized();
    void setShapingSize(float fontSize);

    FT_Library m_library = nullptr;
    FT_Face m_face = nullptr;
    hb_font_t* m_hbFont = nullptr;
    msdfgen::FontHandle* m_fontHandle = nullptr;
    MsdfTextProgram m_program;
    GLuint m_atlasTexture = 0;
    int m_atlasWidth = 2048;
    int m_atlasHeight = 2048;
    int m_atlasCursorX = 1;
    int m_atlasCursorY = 1;
    int m_atlasRowHeight = 0;
    float m_currentShapingSize = 0.0f;
    std::unordered_map<std::uint32_t, Glyph> m_glyphs;
};
