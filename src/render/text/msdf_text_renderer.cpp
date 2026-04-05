#include "render/text/msdf_text_renderer.h"

#include "core/log.h"
#include "font/font_service.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wshadow"
#include <msdfgen-ext.h>
#include <msdfgen.h>
#pragma GCC diagnostic pop

#include <algorithm>
#include <cmath>
#include <cstring>
#include <stdexcept>
#include <vector>

namespace {

constexpr float kAtlasEmSize = 64.0f;
constexpr double kDistanceRange = 5.0;
constexpr int kGlyphPadding = 2;

} // namespace

MsdfTextRenderer::MsdfTextRenderer() = default;

MsdfTextRenderer::~MsdfTextRenderer() { cleanup(); }

void MsdfTextRenderer::initialize(const std::vector<ResolvedFont>& fonts) {
  if (!m_fontSlots.empty()) {
    return;
  }

  if (fonts.empty()) {
    throw std::runtime_error("no fonts provided to MsdfTextRenderer");
  }

  if (FT_Init_FreeType(&m_library) != 0) {
    throw std::runtime_error("FT_Init_FreeType failed");
  }

  for (const auto& font : fonts) {
    FontSlot slot;
    if (FT_New_Face(m_library, font.path.c_str(), font.faceIndex, &slot.face) != 0) {
      logWarn("failed to load fallback font: {}", font.path);
      continue;
    }

    if (FT_Set_Pixel_Sizes(slot.face, 0, static_cast<FT_UInt>(kAtlasEmSize)) != 0) {
      FT_Done_Face(slot.face);
      logWarn("failed to set pixel size for: {}", font.path);
      continue;
    }

    slot.hbFont = hb_ft_font_create_referenced(slot.face);
    if (slot.hbFont == nullptr) {
      FT_Done_Face(slot.face);
      logWarn("hb_ft_font_create_referenced failed for: {}", font.path);
      continue;
    }

    slot.fontHandle = msdfgen::adoptFreetypeFont(slot.face);
    if (slot.fontHandle == nullptr) {
      hb_font_destroy(slot.hbFont);
      FT_Done_Face(slot.face);
      logWarn("msdfgen::adoptFreetypeFont failed for: {}", font.path);
      continue;
    }

    m_fontSlots.push_back(slot);
  }

  if (m_fontSlots.empty()) {
    throw std::runtime_error("no fonts could be loaded");
  }

  m_currentShapingSize = kAtlasEmSize;

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  ensureAtlasPage(0);
  m_program.ensureInitialized();
}

MsdfTextRenderer::TextMetrics MsdfTextRenderer::measure(std::string_view text, float fontSize) {
  if (text.empty()) {
    return {};
  }

  const auto measureSingleLine = [this, fontSize](std::string_view line) {
    auto shaped = shapeWithFallback(line, fontSize);

    const float scale = fontSize / kAtlasEmSize;
    float width = 0.0f;
    float penX = 0.0f;
    float minTop = 0.0f;
    float maxBottom = 0.0f;
    bool hasBounds = false;

    for (const auto& sg : shaped) {
      Glyph& glyph = loadGlyph(sg.slotIndex, sg.glyphIndex);
      const float xOffset = static_cast<float>(sg.position.x_offset) / 64.0f;
      const float yOffset = static_cast<float>(sg.position.y_offset) / 64.0f;
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

      penX += static_cast<float>(sg.position.x_advance) / 64.0f;
    }

    width = std::max(width, penX);
    return TextMetrics{.width = width, .top = minTop, .bottom = maxBottom};
  };

  const float lineAdvance = [&]() {
    const auto metrics = measureSingleLine("Ay");
    return std::max(metrics.bottom - metrics.top, fontSize) + 2.0f;
  }();

  float maxWidth = 0.0f;
  float top = 0.0f;
  float bottom = 0.0f;
  bool hasBounds = false;
  float baselineY = 0.0f;
  std::size_t start = 0;
  while (start <= text.size()) {
    const std::size_t end = text.find('\n', start);
    const std::string_view line = (end == std::string_view::npos) ? text.substr(start) : text.substr(start, end - start);
    auto metrics = measureSingleLine(line);
    maxWidth = std::max(maxWidth, metrics.width);

    if (!hasBounds) {
      top = baselineY + metrics.top;
      bottom = baselineY + metrics.bottom;
      hasBounds = true;
    } else {
      top = std::min(top, baselineY + metrics.top);
      bottom = std::max(bottom, baselineY + metrics.bottom);
    }

    if (end == std::string_view::npos) {
      break;
    }
    baselineY += lineAdvance;
    start = end + 1;
  }

  return TextMetrics{.width = maxWidth, .top = top, .bottom = bottom};
}

MsdfTextRenderer::TruncatedText MsdfTextRenderer::truncate(std::string_view text, float fontSize, float maxWidth) {

  if (text.empty()) {
    return {};
  }

  auto fullMetrics = measure(text, fontSize);
  if (fullMetrics.width <= maxWidth) {
    return TruncatedText{.text = std::string(text), .width = fullMetrics.width};
  }

  static constexpr std::string_view kEllipsis = "\xe2\x80\xa6"; // U+2026 "…"
  auto ellipsisMetrics = measure(kEllipsis, fontSize);
  const float availableWidth = maxWidth - ellipsisMetrics.width;

  if (availableWidth <= 0.0f) {
    return TruncatedText{.text = std::string(kEllipsis), .width = ellipsisMetrics.width};
  }

  // Find the longest prefix that fits. Scan backwards from end on UTF-8 boundaries.
  std::size_t cutPos = text.size();
  while (cutPos > 0) {
    --cutPos;
    // Skip continuation bytes (10xxxxxx)
    if ((static_cast<unsigned char>(text[cutPos]) & 0xC0) == 0x80) {
      continue;
    }

    std::string_view prefix = text.substr(0, cutPos);
    auto prefixMetrics = measure(prefix, fontSize);
    if (prefixMetrics.width <= availableWidth) {
      std::string result(prefix);
      result.append(kEllipsis);
      auto resultMetrics = measure(result, fontSize);
      return TruncatedText{.text = std::move(result), .width = resultMetrics.width};
    }
  }

  return TruncatedText{.text = std::string(kEllipsis), .width = ellipsisMetrics.width};
}

void MsdfTextRenderer::draw(float surfaceWidth, float surfaceHeight, float x, float baselineY, std::string_view text,
                            float fontSize, const Color& color, float rotation, float renderScale) {
  if (text.empty()) {
    return;
  }

  const auto drawSingleLine = [this, surfaceWidth, surfaceHeight, x, fontSize, &color, rotation,
                               renderScale](float lineBaselineY, std::string_view line) {
    if (line.empty()) {
      return;
    }

    auto shaped = shapeWithFallback(line, fontSize);
    const float scale = fontSize / kAtlasEmSize;
    const float pxRange = std::max(static_cast<float>(kDistanceRange) * scale, 1.0f);
    float penX = std::round(x);
    float penY = std::round(lineBaselineY);

    for (const auto& sg : shaped) {
      Glyph& glyph = loadGlyph(sg.slotIndex, sg.glyphIndex);

      if (glyph.atlasWidth > 0.0f && glyph.atlasHeight > 0.0f) {
        const float xOffset = static_cast<float>(sg.position.x_offset) / 64.0f;
        const float yOffset = static_cast<float>(sg.position.y_offset) / 64.0f;
        const float glyphX = penX + xOffset + glyph.bearingX * scale;
        const float glyphY = penY - yOffset - glyph.bearingY * scale;
        const float glyphW = glyph.atlasWidth * scale;
        const float glyphH = glyph.atlasHeight * scale;

        GLuint atlasTexture = m_atlasPages[glyph.atlasPage];
        m_program.draw(atlasTexture, surfaceWidth, surfaceHeight, glyphX, glyphY, glyphW, glyphH, glyph.u0, glyph.v0,
                       glyph.u1, glyph.v1, pxRange, color, rotation, renderScale);
      }

      penX += static_cast<float>(sg.position.x_advance) / 64.0f;
      penY -= static_cast<float>(sg.position.y_advance) / 64.0f;
    }
  };

  const float lineAdvance = [&]() {
    const auto metrics = measure("Ay", fontSize);
    return std::max(metrics.bottom - metrics.top, fontSize) + 2.0f;
  }();

  std::size_t start = 0;
  float lineBaselineY = baselineY;

  while (start <= text.size()) {
    const std::size_t end = text.find('\n', start);
    const std::string_view line = (end == std::string_view::npos) ? text.substr(start) : text.substr(start, end - start);
    drawSingleLine(lineBaselineY, line);
    if (end == std::string_view::npos) {
      break;
    }
    lineBaselineY += lineAdvance;
    start = end + 1;
  }
}

MsdfTextRenderer::TextMetrics MsdfTextRenderer::measureGlyph(char32_t codepoint, float fontSize) {
  if (m_fontSlots.empty()) {
    return {};
  }

  const auto glyphIndex = FT_Get_Char_Index(m_fontSlots[0].face, codepoint);
  if (glyphIndex == 0) {
    return {};
  }

  Glyph& glyph = loadGlyph(0, glyphIndex);
  const float scale = fontSize / kAtlasEmSize;

  FT_Set_Pixel_Sizes(m_fontSlots[0].face, 0, static_cast<FT_UInt>(kAtlasEmSize));
  FT_Load_Glyph(m_fontSlots[0].face, glyphIndex, FT_LOAD_NO_HINTING);
  const float advance = static_cast<float>(m_fontSlots[0].face->glyph->advance.x) / 64.0f * scale;

  const float top = -glyph.bearingY * scale;
  const float bottom = top + glyph.atlasHeight * scale;
  const float width = std::max(glyph.bearingX * scale + glyph.atlasWidth * scale, advance);

  return TextMetrics{.width = width, .top = top, .bottom = bottom};
}

void MsdfTextRenderer::drawGlyph(float surfaceWidth, float surfaceHeight, float x, float baselineY, char32_t codepoint,
                                 float fontSize, const Color& color, float rotation, float renderScale) {
  if (m_fontSlots.empty()) {
    return;
  }

  const auto glyphIndex = FT_Get_Char_Index(m_fontSlots[0].face, codepoint);
  if (glyphIndex == 0) {
    return;
  }

  Glyph& glyph = loadGlyph(0, glyphIndex);
  const float scale = fontSize / kAtlasEmSize;
  const float pxRange = std::max(static_cast<float>(kDistanceRange) * scale, 1.0f);

  if (glyph.atlasWidth > 0.0f && glyph.atlasHeight > 0.0f) {
    const float glyphX = std::round(x) + glyph.bearingX * scale;
    const float glyphY = std::round(baselineY) - glyph.bearingY * scale;
    const float glyphW = glyph.atlasWidth * scale;
    const float glyphH = glyph.atlasHeight * scale;

    GLuint atlasTexture = m_atlasPages[glyph.atlasPage];
    m_program.draw(atlasTexture, surfaceWidth, surfaceHeight, glyphX, glyphY, glyphW, glyphH, glyph.u0, glyph.v0,
                   glyph.u1, glyph.v1, pxRange, color, rotation, renderScale);
  }
}

void MsdfTextRenderer::cleanup() {
  for (auto tex : m_atlasPages) {
    if (tex != 0) {
      glDeleteTextures(1, &tex);
    }
  }
  m_atlasPages.clear();
  m_glyphs.clear();
  m_atlasCursorX = 1;
  m_atlasCursorY = 1;
  m_atlasRowHeight = 0;

  m_program.destroy();

  for (auto& slot : m_fontSlots) {
    if (slot.fontHandle != nullptr) {
      msdfgen::destroyFont(slot.fontHandle);
    }
    if (slot.hbFont != nullptr) {
      hb_font_destroy(slot.hbFont);
    }
    if (slot.face != nullptr) {
      FT_Done_Face(slot.face);
    }
  }
  m_fontSlots.clear();

  if (m_library != nullptr) {
    FT_Done_FreeType(m_library);
    m_library = nullptr;
  }
}

GLuint MsdfTextRenderer::ensureAtlasPage(std::uint32_t page) {
  while (m_atlasPages.size() <= page) {
    GLuint tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    std::vector<std::uint8_t> zeros(static_cast<size_t>(m_atlasWidth) * static_cast<size_t>(m_atlasHeight) * 3, 0);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, m_atlasWidth, m_atlasHeight, 0, GL_RGB, GL_UNSIGNED_BYTE, zeros.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    m_atlasPages.push_back(tex);
  }
  return m_atlasPages[page];
}

void MsdfTextRenderer::setShapingSize(float fontSize) {
  if (std::abs(fontSize - m_currentShapingSize) < 0.01f) {
    return;
  }

  for (auto& slot : m_fontSlots) {
    if (FT_Set_Pixel_Sizes(slot.face, 0, static_cast<FT_UInt>(fontSize)) != 0) {
      continue;
    }

    if (slot.hbFont != nullptr) {
      hb_font_destroy(slot.hbFont);
    }
    slot.hbFont = hb_ft_font_create_referenced(slot.face);
  }

  m_currentShapingSize = fontSize;
}

std::vector<MsdfTextRenderer::ShapedGlyph> MsdfTextRenderer::shapeWithFallback(std::string_view text, float fontSize) {

  setShapingSize(fontSize);

  // Shape with primary font
  hb_buffer_t* buffer = hb_buffer_create();
  hb_buffer_add_utf8(buffer, text.data(), static_cast<int>(text.size()), 0, static_cast<int>(text.size()));
  hb_buffer_guess_segment_properties(buffer);
  hb_shape(m_fontSlots[0].hbFont, buffer, nullptr, 0);

  unsigned int glyphCount = 0;
  hb_glyph_info_t* glyphInfos = hb_buffer_get_glyph_infos(buffer, &glyphCount);
  hb_glyph_position_t* glyphPositions = hb_buffer_get_glyph_positions(buffer, &glyphCount);

  std::vector<ShapedGlyph> result;
  result.reserve(glyphCount);

  // Collect results, marking notdef glyphs for fallback
  std::vector<bool> needsFallback(glyphCount, false);
  bool anyNeedsFallback = false;

  for (unsigned int i = 0; i < glyphCount; ++i) {
    result.push_back(ShapedGlyph{
        .key = makeGlyphKey(0, glyphInfos[i].codepoint),
        .slotIndex = 0,
        .glyphIndex = glyphInfos[i].codepoint,
        .position = glyphPositions[i],
    });

    if (glyphInfos[i].codepoint == 0) {
      needsFallback[i] = true;
      anyNeedsFallback = true;
    }
  }

  hb_buffer_destroy(buffer);

  if (!anyNeedsFallback || m_fontSlots.size() <= 1) {
    return result;
  }

  // For each notdef glyph, find the original character cluster and try fallback fonts.
  // We need the original text to re-shape with fallback fonts.
  // HarfBuzz cluster values map back to byte offsets in the input text.
  // Re-extract cluster info from the primary shaping result.
  buffer = hb_buffer_create();
  hb_buffer_add_utf8(buffer, text.data(), static_cast<int>(text.size()), 0, static_cast<int>(text.size()));
  hb_buffer_guess_segment_properties(buffer);
  hb_shape(m_fontSlots[0].hbFont, buffer, nullptr, 0);

  glyphInfos = hb_buffer_get_glyph_infos(buffer, &glyphCount);

  for (unsigned int i = 0; i < glyphCount; ++i) {
    if (!needsFallback[i]) {
      continue;
    }

    // Get the byte range for this cluster
    const std::uint32_t clusterStart = glyphInfos[i].cluster;
    std::uint32_t clusterEnd;
    if (i + 1 < glyphCount) {
      clusterEnd = glyphInfos[i + 1].cluster;
    } else {
      clusterEnd = static_cast<std::uint32_t>(text.size());
    }

    if (clusterEnd <= clusterStart) {
      // RTL or complex cluster ordering -- skip fallback for this glyph
      continue;
    }

    std::string_view cluster = text.substr(clusterStart, clusterEnd - clusterStart);

    // Try each fallback font
    for (std::uint32_t slotIdx = 1; slotIdx < static_cast<std::uint32_t>(m_fontSlots.size()); ++slotIdx) {
      auto& slot = m_fontSlots[slotIdx];
      if (slot.hbFont == nullptr) {
        continue;
      }

      hb_buffer_t* fbBuf = hb_buffer_create();
      hb_buffer_add_utf8(fbBuf, cluster.data(), static_cast<int>(cluster.size()), 0, static_cast<int>(cluster.size()));
      hb_buffer_guess_segment_properties(fbBuf);
      hb_shape(slot.hbFont, fbBuf, nullptr, 0);

      unsigned int fbCount = 0;
      hb_glyph_info_t* fbInfos = hb_buffer_get_glyph_infos(fbBuf, &fbCount);
      hb_glyph_position_t* fbPositions = hb_buffer_get_glyph_positions(fbBuf, &fbCount);

      // Check if this font has the glyph (not notdef)
      if (fbCount >= 1 && fbInfos[0].codepoint != 0) {
        // Replace with fallback result. For single-cluster, typically 1 glyph.
        result[i] = ShapedGlyph{
            .key = makeGlyphKey(slotIdx, fbInfos[0].codepoint),
            .slotIndex = slotIdx,
            .glyphIndex = fbInfos[0].codepoint,
            .position = fbPositions[0],
        };
        hb_buffer_destroy(fbBuf);
        break;
      }

      hb_buffer_destroy(fbBuf);
    }
  }

  hb_buffer_destroy(buffer);
  return result;
}

MsdfTextRenderer::Glyph& MsdfTextRenderer::loadGlyph(std::uint32_t slotIndex, std::uint32_t glyphIndex) {
  const GlyphKey key = makeGlyphKey(slotIndex, glyphIndex);
  if (auto it = m_glyphs.find(key); it != m_glyphs.end()) {
    return it->second;
  }

  if (slotIndex >= m_fontSlots.size()) {
    auto [it, _] = m_glyphs.emplace(key, Glyph{});
    return it->second;
  }

  auto& slot = m_fontSlots[slotIndex];
  msdfgen::Shape shape;
  double advance = 0.0;
  if (!msdfgen::loadGlyph(shape, slot.fontHandle, msdfgen::GlyphIndex(glyphIndex), msdfgen::FONT_SCALING_EM_NORMALIZED,
                          &advance)) {
    auto [it, _] = m_glyphs.emplace(key, Glyph{});
    return it->second;
  }

  if (shape.contours.empty()) {
    auto [it, _] = m_glyphs.emplace(key, Glyph{});
    return it->second;
  }

  shape.normalize();
  shape.orientContours();
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
  const msdfgen::Projection projection(msdfgen::Vector2(emSize, emSize),
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

  // Check if we need to advance to next row or next page
  if (m_atlasCursorX + paddedW > m_atlasWidth) {
    m_atlasCursorX = 1;
    m_atlasCursorY += m_atlasRowHeight + 1;
    m_atlasRowHeight = 0;
  }

  std::uint32_t currentPage = m_atlasPages.empty() ? 0 : static_cast<std::uint32_t>(m_atlasPages.size() - 1);

  if (m_atlasCursorY + paddedH > m_atlasHeight) {
    // Current page is full, allocate a new one
    currentPage = static_cast<std::uint32_t>(m_atlasPages.size());
    ensureAtlasPage(currentPage);
    m_atlasCursorX = 1;
    m_atlasCursorY = 1;
    m_atlasRowHeight = 0;
    logDebug("allocated atlas page {}", currentPage);
  }

  const int destX = m_atlasCursorX + kGlyphPadding;
  const int destY = m_atlasCursorY + kGlyphPadding;

  glBindTexture(GL_TEXTURE_2D, m_atlasPages[currentPage]);
  glTexSubImage2D(GL_TEXTURE_2D, 0, destX, destY, glyphW, glyphH, GL_RGB, GL_UNSIGNED_BYTE, pixels.data());

  const auto atlasW = static_cast<float>(m_atlasWidth);
  const auto atlasH = static_cast<float>(m_atlasHeight);

  Glyph glyph{
      .atlasWidth = static_cast<float>(glyphW),
      .atlasHeight = static_cast<float>(glyphH),
      .bearingX = static_cast<float>(pxLeft),
      .bearingY = static_cast<float>(pxTop),
      .u0 = static_cast<float>(destX) / atlasW,
      .v0 = static_cast<float>(destY) / atlasH,
      .u1 = static_cast<float>(destX + glyphW) / atlasW,
      .v1 = static_cast<float>(destY + glyphH) / atlasH,
      .atlasPage = currentPage,
  };

  m_atlasCursorX += paddedW + 1;
  m_atlasRowHeight = std::max(m_atlasRowHeight, paddedH);

  auto [it, _] = m_glyphs.emplace(key, glyph);
  return it->second;
}
