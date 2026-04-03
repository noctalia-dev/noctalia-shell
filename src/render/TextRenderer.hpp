#pragma once

#include "render/Color.hpp"
#include "render/TextProgram.hpp"

#include <ft2build.h>
#include FT_FREETYPE_H
#include <hb-ft.h>

#include <cstdint>
#include <string_view>
#include <unordered_map>

class TextRenderer {
public:
    struct TextMetrics {
        float width = 0.0f;
        float top = 0.0f;
        float bottom = 0.0f;
    };

    TextRenderer();
    ~TextRenderer();

    TextRenderer(const TextRenderer&) = delete;
    TextRenderer& operator=(const TextRenderer&) = delete;

    void initialize();
    [[nodiscard]] TextMetrics measure(std::string_view text);
    void draw(float surfaceWidth,
              float surfaceHeight,
              float x,
              float baselineY,
              std::string_view text,
              const Color& color);
    void cleanup();

private:
    struct Glyph {
        float width = 0.0f;
        float height = 0.0f;
        float bearingX = 0.0f;
        float bearingY = 0.0f;
        float u0 = 0.0f;
        float v0 = 0.0f;
        float u1 = 1.0f;
        float v1 = 1.0f;
    };

    Glyph& loadGlyph(std::uint32_t glyphIndex);
    void ensureAtlasInitialized();

    FT_Library m_library = nullptr;
    FT_Face m_face = nullptr;
    hb_font_t* m_hbFont = nullptr;
    TextProgram m_program;
    GLuint m_atlasTexture = 0;
    int m_atlasWidth = 1024;
    int m_atlasHeight = 1024;
    int m_atlasCursorX = 1;
    int m_atlasCursorY = 1;
    int m_atlasRowHeight = 0;
    std::unordered_map<std::uint32_t, Glyph> m_glyphs;
};
