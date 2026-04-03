#include "render/MsdfTextRenderer.hpp"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"
#include <msdfgen.h>
#include <msdfgen-ext.h>
#pragma GCC diagnostic pop

#include <algorithm>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace {

constexpr auto kDefaultFontPath = "/usr/share/fonts/google-roboto/Roboto-Medium.ttf";
constexpr float kAtlasEmSize = 48.0f;
constexpr double kDistanceRange = 4.0;
constexpr int kGlyphPadding = 2;

} // namespace

MsdfTextRenderer::MsdfTextRenderer() = default;

MsdfTextRenderer::~MsdfTextRenderer() {
    cleanup();
}

void MsdfTextRenderer::initialize() {
    if (m_face != nullptr) {
        return;
    }

    if (FT_Init_FreeType(&m_library) != 0) {
        throw std::runtime_error("FT_Init_FreeType failed");
    }

    if (FT_New_Face(m_library, kDefaultFontPath, 0, &m_face) != 0) {
        throw std::runtime_error("FT_New_Face failed");
    }

    if (FT_Set_Pixel_Sizes(m_face, 0, static_cast<FT_UInt>(kAtlasEmSize)) != 0) {
        throw std::runtime_error("FT_Set_Pixel_Sizes failed");
    }

    m_hbFont = hb_ft_font_create_referenced(m_face);
    if (m_hbFont == nullptr) {
        throw std::runtime_error("hb_ft_font_create_referenced failed");
    }
    m_currentShapingSize = kAtlasEmSize;

    m_fontHandle = msdfgen::adoptFreetypeFont(m_face);
    if (m_fontHandle == nullptr) {
        throw std::runtime_error("msdfgen::adoptFreetypeFont failed");
    }

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    ensureAtlasInitialized();
    m_program.ensureInitialized();
}

MsdfTextRenderer::TextMetrics MsdfTextRenderer::measure(std::string_view text, float fontSize) {
    if (text.empty()) {
        return {};
    }

    setShapingSize(fontSize);

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

    const float scale = fontSize / kAtlasEmSize;
    float width = 0.0f;
    float penX = 0.0f;
    float minTop = 0.0f;
    float maxBottom = 0.0f;
    bool hasBounds = false;

    for (unsigned int i = 0; i < glyphCount; ++i) {
        const auto glyphIndex = glyphInfos[i].codepoint;
        Glyph& glyph = loadGlyph(glyphIndex);
        const float xOffset = static_cast<float>(glyphPositions[i].x_offset) / 64.0f;
        const float yOffset = static_cast<float>(glyphPositions[i].y_offset) / 64.0f;
        const float glyphLeft = penX + xOffset + glyph.bearingX * scale;
        const float glyphTop = -yOffset - glyph.bearingY * scale;
        const float glyphBottom = glyphTop + glyph.atlasHeight * scale;
        const float glyphRight = glyphLeft + glyph.atlasWidth * scale;

        if (glyph.atlasWidth > 0.0f && glyph.atlasHeight > 0.0f) {
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

        penX += static_cast<float>(glyphPositions[i].x_advance) / 64.0f;
    }

    width = std::max(width, penX);

    hb_buffer_destroy(buffer);

    return TextMetrics{
        .width = width,
        .top = minTop,
        .bottom = maxBottom,
    };
}

void MsdfTextRenderer::draw(float surfaceWidth,
                            float surfaceHeight,
                            float x,
                            float baselineY,
                            std::string_view text,
                            float fontSize,
                            const Color& color) {
    if (text.empty()) {
        return;
    }

    setShapingSize(fontSize);

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

    const float scale = fontSize / kAtlasEmSize;
    const float pxRange = std::max(static_cast<float>(kDistanceRange) * scale, 1.0f);
    float penX = x;
    float penY = std::round(baselineY);

    for (unsigned int i = 0; i < glyphCount; ++i) {
        const auto glyphIndex = glyphInfos[i].codepoint;
        Glyph& glyph = loadGlyph(glyphIndex);

        if (glyph.atlasWidth > 0.0f && glyph.atlasHeight > 0.0f) {
            const float xOffset = static_cast<float>(glyphPositions[i].x_offset) / 64.0f;
            const float yOffset = static_cast<float>(glyphPositions[i].y_offset) / 64.0f;
            const float glyphX = penX + xOffset + glyph.bearingX * scale;
            const float glyphY = penY - yOffset - glyph.bearingY * scale;
            const float glyphW = glyph.atlasWidth * scale;
            const float glyphH = glyph.atlasHeight * scale;

            m_program.draw(
                m_atlasTexture,
                surfaceWidth,
                surfaceHeight,
                glyphX,
                glyphY,
                glyphW,
                glyphH,
                glyph.u0,
                glyph.v0,
                glyph.u1,
                glyph.v1,
                pxRange,
                color);
        }

        penX += static_cast<float>(glyphPositions[i].x_advance) / 64.0f;
        penY -= static_cast<float>(glyphPositions[i].y_advance) / 64.0f;
    }

    hb_buffer_destroy(buffer);
}

void MsdfTextRenderer::cleanup() {
    if (m_atlasTexture != 0) {
        glDeleteTextures(1, &m_atlasTexture);
        m_atlasTexture = 0;
    }
    m_glyphs.clear();
    m_atlasCursorX = 1;
    m_atlasCursorY = 1;
    m_atlasRowHeight = 0;

    m_program.destroy();

    if (m_fontHandle != nullptr) {
        msdfgen::destroyFont(m_fontHandle);
        m_fontHandle = nullptr;
    }

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

void MsdfTextRenderer::ensureAtlasInitialized() {
    if (m_atlasTexture != 0) {
        return;
    }

    glGenTextures(1, &m_atlasTexture);
    glBindTexture(GL_TEXTURE_2D, m_atlasTexture);
    glTexImage2D(
        GL_TEXTURE_2D,
        0,
        GL_RGB,
        m_atlasWidth,
        m_atlasHeight,
        0,
        GL_RGB,
        GL_UNSIGNED_BYTE,
        nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
}

void MsdfTextRenderer::setShapingSize(float fontSize) {
    if (std::abs(fontSize - m_currentShapingSize) < 0.01f) {
        return;
    }

    if (FT_Set_Pixel_Sizes(m_face, 0, static_cast<FT_UInt>(fontSize)) != 0) {
        throw std::runtime_error("FT_Set_Pixel_Sizes failed");
    }

    if (m_hbFont != nullptr) {
        hb_font_destroy(m_hbFont);
    }
    m_hbFont = hb_ft_font_create_referenced(m_face);
    if (m_hbFont == nullptr) {
        throw std::runtime_error("hb_ft_font_create_referenced failed");
    }

    m_currentShapingSize = fontSize;
}

MsdfTextRenderer::Glyph& MsdfTextRenderer::loadGlyph(std::uint32_t glyphIndex) {
    if (auto it = m_glyphs.find(glyphIndex); it != m_glyphs.end()) {
        return it->second;
    }

    msdfgen::Shape shape;
    double advance = 0.0;
    if (!msdfgen::loadGlyph(shape, m_fontHandle, msdfgen::GlyphIndex(glyphIndex),
                            msdfgen::FONT_SCALING_EM_NORMALIZED, &advance)) {
        auto [it, _] = m_glyphs.emplace(glyphIndex, Glyph{});
        return it->second;
    }

    if (shape.contours.empty()) {
        auto [it, _] = m_glyphs.emplace(glyphIndex, Glyph{});
        return it->second;
    }

    shape.normalize();
    msdfgen::Shape::Bounds bounds = shape.getBounds();

    const auto emSize = static_cast<double>(kAtlasEmSize);
    const double pxLeft = bounds.l * emSize - kDistanceRange;
    const double pxBottom = bounds.b * emSize - kDistanceRange;
    const double pxRight = bounds.r * emSize + kDistanceRange;
    const double pxTop = bounds.t * emSize + kDistanceRange;

    const int glyphW = std::max(1, static_cast<int>(std::ceil(pxRight - pxLeft)));
    const int glyphH = std::max(1, static_cast<int>(std::ceil(pxTop - pxBottom)));

    msdfgen::edgeColoringSimple(shape, 3.0);

    msdfgen::Bitmap<float, 3> msdf(glyphW, glyphH);
    const msdfgen::Projection projection(
        msdfgen::Vector2(emSize, emSize),
        msdfgen::Vector2(-pxLeft / emSize, -pxBottom / emSize));
    const msdfgen::Range range(kDistanceRange / emSize);
    msdfgen::generateMSDF(msdf, shape, projection, range);

    const auto pixelCount = static_cast<std::size_t>(glyphW * glyphH * 3);
    std::vector<unsigned char> pixels(pixelCount);
    for (int y = 0; y < glyphH; ++y) {
        const int srcY = glyphH - 1 - y;
        for (int x = 0; x < glyphW; ++x) {
            const auto dstIdx = static_cast<std::size_t>((y * glyphW + x) * 3);
            const float* pixel = msdf(x, srcY);
            pixels[dstIdx + 0] = msdfgen::pixelFloatToByte(pixel[0]);
            pixels[dstIdx + 1] = msdfgen::pixelFloatToByte(pixel[1]);
            pixels[dstIdx + 2] = msdfgen::pixelFloatToByte(pixel[2]);
        }
    }

    const int paddedW = glyphW + kGlyphPadding * 2;
    const int paddedH = glyphH + kGlyphPadding * 2;

    if (m_atlasCursorX + paddedW > m_atlasWidth) {
        m_atlasCursorX = 1;
        m_atlasCursorY += m_atlasRowHeight + 1;
        m_atlasRowHeight = 0;
    }

    if (m_atlasCursorY + paddedH > m_atlasHeight) {
        throw std::runtime_error("MSDF text atlas is full");
    }

    const int destX = m_atlasCursorX + kGlyphPadding;
    const int destY = m_atlasCursorY + kGlyphPadding;

    glBindTexture(GL_TEXTURE_2D, m_atlasTexture);
    glTexSubImage2D(
        GL_TEXTURE_2D,
        0,
        destX,
        destY,
        glyphW,
        glyphH,
        GL_RGB,
        GL_UNSIGNED_BYTE,
        pixels.data());

    Glyph glyph{
        .atlasWidth = static_cast<float>(glyphW),
        .atlasHeight = static_cast<float>(glyphH),
        .bearingX = static_cast<float>(pxLeft),
        .bearingY = static_cast<float>(pxTop),
        .u0 = static_cast<float>(destX) / static_cast<float>(m_atlasWidth),
        .v0 = static_cast<float>(destY) / static_cast<float>(m_atlasHeight),
        .u1 = static_cast<float>(destX + glyphW) / static_cast<float>(m_atlasWidth),
        .v1 = static_cast<float>(destY + glyphH) / static_cast<float>(m_atlasHeight),
    };

    m_atlasCursorX += paddedW + 1;
    m_atlasRowHeight = std::max(m_atlasRowHeight, paddedH);

    auto [it, _] = m_glyphs.emplace(glyphIndex, glyph);
    return it->second;
}
