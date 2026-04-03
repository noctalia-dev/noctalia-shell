#include "render/TextRenderer.hpp"

#include <algorithm>
#include <array>
#include <cstring>
#include <cmath>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr auto kDefaultFontPath = "/usr/share/fonts/google-roboto/Roboto-Medium.ttf";
constexpr unsigned int kFontPixelSize = 14;
constexpr float kRasterScale = 1.0f;
constexpr int kGlyphPadding = 1;

} // namespace

TextRenderer::TextRenderer() = default;

TextRenderer::~TextRenderer() {
    cleanup();
}

void TextRenderer::initialize() {
    if (m_face != nullptr) {
        return;
    }

    if (FT_Init_FreeType(&m_library) != 0) {
        throw std::runtime_error("FT_Init_FreeType failed");
    }

    if (FT_New_Face(m_library, kDefaultFontPath, 0, &m_face) != 0) {
        throw std::runtime_error("FT_New_Face failed");
    }

    if (FT_Set_Pixel_Sizes(m_face, 0, static_cast<FT_UInt>(kFontPixelSize)) != 0) {
        throw std::runtime_error("FT_Set_Pixel_Sizes failed");
    }

    m_hbFont = hb_ft_font_create_referenced(m_face);
    if (m_hbFont == nullptr) {
        throw std::runtime_error("hb_ft_font_create_referenced failed");
    }

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    ensureAtlasInitialized();
    m_program.ensureInitialized();
}

TextRenderer::TextMetrics TextRenderer::measure(std::string_view text) {
    if (text.empty()) {
        return {};
    }

    hb_buffer_t* buffer = hb_buffer_create();
    if (buffer == nullptr) {
        throw std::runtime_error("hb_buffer_create failed");
    }

    hb_buffer_add_utf8(buffer, text.data(), static_cast<int>(text.size()), 0, static_cast<int>(text.size()));
    hb_buffer_guess_segment_properties(buffer);
    hb_shape(m_hbFont, buffer, nullptr, 0);

    unsigned int glyphCount = 0;
    hb_glyph_position_t* glyphPositions = hb_buffer_get_glyph_positions(buffer, &glyphCount);
    hb_glyph_info_t* glyphInfos = hb_buffer_get_glyph_infos(buffer, &glyphCount);

    float width = 0.0f;
    float penX = 0.0f;
    float minTop = 0.0f;
    float maxBottom = 0.0f;
    bool hasBounds = false;

    for (unsigned int i = 0; i < glyphCount; ++i) {
        const auto glyphIndex = glyphInfos[i].codepoint;
        Glyph& glyph = loadGlyph(glyphIndex);
        const float xOffset = static_cast<float>(glyphPositions[i].x_offset) / 64.0f / kRasterScale;
        const float yOffset = static_cast<float>(glyphPositions[i].y_offset) / 64.0f / kRasterScale;
        const float glyphLeft = penX + xOffset + glyph.bearingX;
        const float glyphTop = -yOffset - glyph.bearingY;
        const float glyphBottom = glyphTop + glyph.height;
        const float glyphRight = glyphLeft + glyph.width;

        if (glyph.width > 0.0f && glyph.height > 0.0f) {
            if (!hasBounds) {
                minTop = glyphTop;
                maxBottom = glyphBottom;
                width = glyphRight;
                hasBounds = true;
            } else {
                minTop = std::min(minTop, glyphTop);
                maxBottom = std::max(maxBottom, glyphBottom);
                width = std::max(width, glyphRight);
            }
        }

        penX += static_cast<float>(glyphPositions[i].x_advance) / 64.0f / kRasterScale;
    }

    width = std::max(width, penX);

    hb_buffer_destroy(buffer);

    return TextMetrics{
        .width = width,
        .top = minTop,
        .bottom = maxBottom,
    };
}

void TextRenderer::draw(float surfaceWidth,
                        float surfaceHeight,
                        float x,
                        float baselineY,
                        std::string_view text,
                        const Color& color) {
    if (text.empty()) {
        return;
    }

    hb_buffer_t* buffer = hb_buffer_create();
    if (buffer == nullptr) {
        throw std::runtime_error("hb_buffer_create failed");
    }

    hb_buffer_add_utf8(buffer, text.data(), static_cast<int>(text.size()), 0, static_cast<int>(text.size()));
    hb_buffer_guess_segment_properties(buffer);
    hb_shape(m_hbFont, buffer, nullptr, 0);

    unsigned int glyphCount = 0;
    hb_glyph_info_t* glyphInfos = hb_buffer_get_glyph_infos(buffer, &glyphCount);
    hb_glyph_position_t* glyphPositions = hb_buffer_get_glyph_positions(buffer, &glyphCount);

    float penX = x;
    float penY = std::round(baselineY);

    for (unsigned int i = 0; i < glyphCount; ++i) {
        const auto glyphIndex = glyphInfos[i].codepoint;
        Glyph& glyph = loadGlyph(glyphIndex);

        const float xOffset = static_cast<float>(glyphPositions[i].x_offset) / 64.0f / kRasterScale;
        const float yOffset = static_cast<float>(glyphPositions[i].y_offset) / 64.0f / kRasterScale;
        const float glyphX = std::round(penX + xOffset + glyph.bearingX);
        const float glyphY = std::round(penY - yOffset - glyph.bearingY);

        m_program.draw(
            m_atlasTexture,
            surfaceWidth,
            surfaceHeight,
            glyphX,
            glyphY,
            glyph.width,
            glyph.height,
            glyph.u0,
            glyph.v0,
            glyph.u1,
            glyph.v1,
            color);

        penX += static_cast<float>(glyphPositions[i].x_advance) / 64.0f / kRasterScale;
        penY -= static_cast<float>(glyphPositions[i].y_advance) / 64.0f / kRasterScale;
    }

    hb_buffer_destroy(buffer);
}

void TextRenderer::cleanup() {
    if (m_atlasTexture != 0) {
        glDeleteTextures(1, &m_atlasTexture);
        m_atlasTexture = 0;
    }
    m_glyphs.clear();
    m_atlasCursorX = 1;
    m_atlasCursorY = 1;
    m_atlasRowHeight = 0;

    m_program.destroy();

    if (m_hbFont != nullptr) {
        hb_font_destroy(m_hbFont);
        m_hbFont = nullptr;
    }

    if (m_face != nullptr) {
        FT_Done_Face(m_face);
        m_face = nullptr;
    }

    if (m_library != nullptr) {
        FT_Done_FreeType(m_library);
        m_library = nullptr;
    }
}

void TextRenderer::ensureAtlasInitialized() {
    if (m_atlasTexture != 0) {
        return;
    }

    glGenTextures(1, &m_atlasTexture);
    glBindTexture(GL_TEXTURE_2D, m_atlasTexture);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_ALPHA,
        m_atlasWidth,
        m_atlasHeight,
        0,
        GL_ALPHA,
        GL_UNSIGNED_BYTE,
        nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
}

TextRenderer::Glyph& TextRenderer::loadGlyph(std::uint32_t glyphIndex) {
    if (auto it = m_glyphs.find(glyphIndex); it != m_glyphs.end()) {
        return it->second;
    }

    if (FT_Load_Glyph(m_face, glyphIndex, FT_LOAD_DEFAULT | FT_LOAD_TARGET_LIGHT) != 0) {
        throw std::runtime_error("FT_Load_Glyph failed");
    }

    if (FT_Render_Glyph(m_face->glyph, FT_RENDER_MODE_NORMAL) != 0) {
        throw std::runtime_error("FT_Render_Glyph failed");
    }

    const FT_GlyphSlot slot = m_face->glyph;
    const int glyphPixelWidth = static_cast<int>(slot->bitmap.width);
    const int paddedWidth = glyphPixelWidth + (kGlyphPadding * 2);
    const int paddedHeight = static_cast<int>(slot->bitmap.rows) + (kGlyphPadding * 2);

    if (m_atlasCursorX + paddedWidth > m_atlasWidth) {
        m_atlasCursorX = 1;
        m_atlasCursorY += m_atlasRowHeight + 1;
        m_atlasRowHeight = 0;
    }

    if (m_atlasCursorY + paddedHeight > m_atlasHeight) {
        throw std::runtime_error("text atlas is full");
    }

    std::vector<unsigned char> paddedBitmap(static_cast<std::size_t>(paddedWidth * paddedHeight), 0);

    for (unsigned int row = 0; row < slot->bitmap.rows; ++row) {
        const auto* src = slot->bitmap.buffer + row * slot->bitmap.pitch;
        auto* dst = paddedBitmap.data()
            + ((static_cast<std::size_t>(row) + static_cast<std::size_t>(kGlyphPadding))
                * static_cast<std::size_t>(paddedWidth))
            + static_cast<std::size_t>(kGlyphPadding);
        std::memcpy(dst, src, static_cast<std::size_t>(slot->bitmap.width));
    }

    glBindTexture(GL_TEXTURE_2D, m_atlasTexture);
    glTexSubImage2D(
        GL_TEXTURE_2D,
        0,
        m_atlasCursorX,
        m_atlasCursorY,
        paddedWidth,
        paddedHeight,
        GL_ALPHA,
        GL_UNSIGNED_BYTE,
        paddedBitmap.data());

    Glyph glyph{
        .width = static_cast<float>(glyphPixelWidth) / kRasterScale,
        .height = static_cast<float>(slot->bitmap.rows) / kRasterScale,
        .bearingX = static_cast<float>(slot->bitmap_left) / kRasterScale,
        .bearingY = static_cast<float>(slot->bitmap_top) / kRasterScale,
        .u0 = (static_cast<float>(m_atlasCursorX + kGlyphPadding) + 0.5f) / static_cast<float>(m_atlasWidth),
        .v0 = (static_cast<float>(m_atlasCursorY + kGlyphPadding) + 0.5f) / static_cast<float>(m_atlasHeight),
        .u1 = (static_cast<float>(m_atlasCursorX + kGlyphPadding + glyphPixelWidth) - 0.5f)
            / static_cast<float>(m_atlasWidth),
        .v1 = (static_cast<float>(m_atlasCursorY + kGlyphPadding + slot->bitmap.rows) - 0.5f)
            / static_cast<float>(m_atlasHeight),
    };

    m_atlasCursorX += paddedWidth + 1;
    m_atlasRowHeight = std::max(m_atlasRowHeight, paddedHeight);

    auto [it, _] = m_glyphs.emplace(glyphIndex, glyph);
    return it->second;
}
