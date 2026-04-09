#include "render/text/msdf_text_renderer.h"

#include "core/log.h"
#include "font/font_service.h"
#include "render/text/emoji_data.h"

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
// Color emoji (COLR v1 / CBDT / sbix) are rasterized at a higher resolution so
// that GL_LINEAR_MIPMAP_LINEAR filtering produces crisp results when displayed
// at typical UI sizes (14-32 px).  Must be a power-of-two multiple of kAtlasEmSize.
constexpr float kColorAtlasEmSize = 256.0f;

// --- Emoji run segmentation helpers ---

// Decode one UTF-8 codepoint and advance ptr. Returns 0 at end of string.
char32_t nextUtf8Codepoint(const char*& ptr, const char* end) {
  if (ptr >= end) {
    return 0;
  }
  const auto c0 = static_cast<unsigned char>(*ptr);
  if (c0 < 0x80) {
    return static_cast<char32_t>(*ptr++);
  }
  if (c0 < 0xC2 || ptr + 1 >= end) {
    ++ptr;
    return 0xFFFD;
  }
  if (c0 < 0xE0) {
    char32_t cp = ((c0 & 0x1Fu) << 6u) | (static_cast<unsigned char>(ptr[1]) & 0x3Fu);
    ptr += 2;
    return cp;
  }
  if (c0 < 0xF0) {
    if (ptr + 2 >= end) {
      ++ptr;
      return 0xFFFD;
    }
    char32_t cp = ((c0 & 0x0Fu) << 12u) | ((static_cast<unsigned char>(ptr[1]) & 0x3Fu) << 6u) |
                  (static_cast<unsigned char>(ptr[2]) & 0x3Fu);
    ptr += 3;
    return cp;
  }
  if (ptr + 3 >= end) {
    ++ptr;
    return 0xFFFD;
  }
  char32_t cp = ((c0 & 0x07u) << 18u) | ((static_cast<unsigned char>(ptr[1]) & 0x3Fu) << 12u) |
                ((static_cast<unsigned char>(ptr[2]) & 0x3Fu) << 6u) |
                (static_cast<unsigned char>(ptr[3]) & 0x3Fu);
  ptr += 4;
  return cp;
}

struct TextRun {
  std::uint32_t byteStart;
  std::uint32_t byteEnd;
  bool isEmoji;
};

// Segment UTF-8 text into emoji vs non-emoji runs.
// A run is emoji if its codepoints have Unicode Emoji_Presentation, or are
// part of an ongoing emoji sequence joined by ZWJ / VS16 / tags / keycap.
//
// Key edge case: ZWJ sequences like 😶‍🌫️ (U+1F636 U+200D U+1F32B U+FE0F).
// U+1F32B (FOG) has the Unicode `Emoji` property but NOT `Emoji_Presentation`,
// so it would otherwise split the run. The fix: after a ZWJ inside an emoji run,
// the very next codepoint always continues the emoji run regardless of its own
// presentation class (it is a ZWJ sequence component by definition).
std::vector<TextRun> segmentEmojiRuns(std::string_view text) {
  std::vector<TextRun> runs;
  const char* ptr      = text.data();
  const char* end      = text.data() + text.size();
  bool        inEmoji  = false;
  bool        afterZwj = false; // true for exactly one codepoint after ZWJ

  while (ptr < end) {
    const char*    cpStart = ptr;
    const char32_t cp      = nextUtf8Codepoint(ptr, end);
    if (cp == 0) {
      break;
    }

    bool thisEmoji;
    if (emoji::isEmojiPresentation(cp)) {
      thisEmoji = true;
    } else if ((emoji::isEmojiContinuer(cp) || afterZwj) && inEmoji) {
      // isEmojiContinuer: VS16 / ZWJ / keycap / tag continuing an emoji run.
      // afterZwj: the codepoint immediately following ZWJ in an emoji run
      //   continues the run even if it lacks Emoji_Presentation on its own
      //   (e.g. 🌫 U+1F32B in "face in clouds" 😶‍🌫️).
      thisEmoji = true;
    } else if (cp > 0x7Fu) {
      // Non-ASCII codepoint with Emoji (but not Emoji_Presentation) property.
      // Peek ahead: if the next codepoint is VS16 (U+FE0F), this codepoint is
      // being explicitly forced to emoji presentation (e.g. 🌬️ = U+1F32C + VS16).
      // Route it to the emoji font so HarfBuzz sees the full VS16 sequence.
      const char* peek = ptr;
      thisEmoji        = (nextUtf8Codepoint(peek, end) == 0xFE0Fu);
    } else {
      thisEmoji = false;
    }

    afterZwj = (cp == 0x200Du) && thisEmoji;

    const auto byteOffset = static_cast<std::uint32_t>(cpStart - text.data());

    if (runs.empty()) {
      runs.push_back({byteOffset, 0, thisEmoji});
    } else if (thisEmoji != inEmoji) {
      runs.back().byteEnd = byteOffset;
      runs.push_back({byteOffset, 0, thisEmoji});
    }

    inEmoji = thisEmoji;
  }

  if (!runs.empty()) {
    runs.back().byteEnd = static_cast<std::uint32_t>(text.size());
  }

  return runs;
}

constexpr double kDistanceRange = 5.0;
constexpr int kGlyphPadding = 2;

constexpr Logger kLog("font");

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
      kLog.warn("failed to load fallback font: {}", font.path);
      continue;
    }

    if (FT_Set_Pixel_Sizes(slot.face, 0, static_cast<FT_UInt>(kAtlasEmSize)) != 0) {
      FT_Done_Face(slot.face);
      kLog.warn("failed to set pixel size for: {}", font.path);
      continue;
    }

    slot.hbFont = hb_ft_font_create_referenced(slot.face);
    if (slot.hbFont == nullptr) {
      FT_Done_Face(slot.face);
      kLog.warn("hb_ft_font_create_referenced failed for: {}", font.path);
      continue;
    }

    slot.fontHandle = msdfgen::adoptFreetypeFont(slot.face);
    if (slot.fontHandle == nullptr) {
      hb_font_destroy(slot.hbFont);
      FT_Done_Face(slot.face);
      kLog.warn("msdfgen::adoptFreetypeFont failed for: {}", font.path);
      continue;
    }

    m_fontSlots.push_back(slot);
  }

  if (m_fontSlots.empty()) {
    throw std::runtime_error("no fonts could be loaded");
  }

  // Find the dedicated color emoji font slot (first FT_HAS_COLOR face).
  m_emojiSlotIndex = UINT32_MAX;
  for (std::uint32_t i = 0; i < static_cast<std::uint32_t>(m_fontSlots.size()); ++i) {
    if (FT_HAS_COLOR(m_fontSlots[i].face)) {
      m_emojiSlotIndex = i;
      kLog.debug("emoji slot: {} ({})", i, fonts[i].path);
      break;
    }
  }

  m_currentShapingSize = kAtlasEmSize;

  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  ensureAtlasPage(0);
  m_program.ensureInitialized();
  m_colorProgram.ensureInitialized();
}

void MsdfTextRenderer::prepareAtlasUploadState() const {
  glActiveTexture(GL_TEXTURE0);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
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
    float minLeft = 0.0f;
    float maxRight = 0.0f;
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
          minLeft = glyphLeft;
          maxRight = glyphRight;
          minTop = glyphTop;
          maxBottom = glyphBottom;
          width = glyphRight;
          hasBounds = true;
        } else {
          minLeft = std::min(minLeft, glyphLeft);
          maxRight = std::max(maxRight, glyphRight);
          minTop = std::min(minTop, glyphTop);
          maxBottom = std::max(maxBottom, glyphBottom);
          width = std::max(width, glyphRight);
        }
      }

      penX += static_cast<float>(sg.position.x_advance) / 64.0f;
    }

    width = std::max(width, penX);
    return TextMetrics{
        .width = width,
        .left = hasBounds ? minLeft : 0.0f,
        .right = hasBounds ? maxRight : width,
        .top = minTop,
        .bottom = maxBottom,
    };
  };

  const float lineAdvance = [&]() {
    const auto metrics = measureSingleLine("Ay");
    return std::max(metrics.bottom - metrics.top, fontSize) + 2.0f;
  }();

  float maxWidth = 0.0f;
  float left = 0.0f;
  float right = 0.0f;
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
      left = metrics.left;
      right = metrics.right;
      top = baselineY + metrics.top;
      bottom = baselineY + metrics.bottom;
      hasBounds = true;
    } else {
      left = std::min(left, metrics.left);
      right = std::max(right, metrics.right);
      top = std::min(top, baselineY + metrics.top);
      bottom = std::max(bottom, baselineY + metrics.bottom);
    }

    if (end == std::string_view::npos) {
      break;
    }
    baselineY += lineAdvance;
    start = end + 1;
  }

  return TextMetrics{.width = maxWidth, .left = left, .right = right, .top = top, .bottom = bottom};
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
                            float fontSize, const Color& color, const Mat3& transform) {
  if (text.empty()) {
    return;
  }

  const auto drawSingleLine = [this, surfaceWidth, surfaceHeight, x, fontSize, &color,
                               &transform](float lineBaselineY, std::string_view line) {
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

        if (glyph.isColor) {
          GLuint colorTexture = m_colorAtlasPages[glyph.atlasPage];
          m_colorProgram.draw(colorTexture, surfaceWidth, surfaceHeight, glyphW, glyphH, glyph.u0, glyph.v0, glyph.u1,
                              glyph.v1, color.a, transform * Mat3::translation(glyphX, glyphY));
        } else {
          GLuint atlasTexture = m_atlasPages[glyph.atlasPage];
          m_program.draw(atlasTexture, surfaceWidth, surfaceHeight, glyphW, glyphH, glyph.u0, glyph.v0, glyph.u1,
                         glyph.v1, pxRange, color, transform * Mat3::translation(glyphX, glyphY));
        }
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
  const float left = glyph.bearingX * scale;
  const float right = left + glyph.atlasWidth * scale;
  const float width = std::max(glyph.bearingX * scale + glyph.atlasWidth * scale, advance);

  return TextMetrics{.width = width, .left = left, .right = right, .top = top, .bottom = bottom};
}

void MsdfTextRenderer::drawGlyph(float surfaceWidth, float surfaceHeight, float x, float baselineY, char32_t codepoint,
                                 float fontSize, const Color& color, const Mat3& transform) {
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
    m_program.draw(atlasTexture, surfaceWidth, surfaceHeight, glyphW, glyphH, glyph.u0, glyph.v0, glyph.u1, glyph.v1,
                   pxRange, color, transform * Mat3::translation(glyphX, glyphY));
  }
}

void MsdfTextRenderer::cleanup() {
  for (auto tex : m_atlasPages) {
    if (tex != 0) {
      glDeleteTextures(1, &tex);
    }
  }
  m_atlasPages.clear();
  for (auto tex : m_colorAtlasPages) {
    if (tex != 0) {
      glDeleteTextures(1, &tex);
    }
  }
  m_colorAtlasPages.clear();
  m_glyphs.clear();
  m_atlasCursorX = 1;
  m_atlasCursorY = 1;
  m_atlasRowHeight = 0;
  m_colorAtlasCursorX = 1;
  m_colorAtlasCursorY = 1;
  m_colorAtlasRowHeight = 0;

  m_program.destroy();
  m_colorProgram.destroy();

  for (auto& slot : m_fontSlots) {
    if (slot.cairoFace != nullptr) {
      cairo_font_face_destroy(slot.cairoFace);
      slot.cairoFace = nullptr;
    }
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
    prepareAtlasUploadState();
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

GLuint MsdfTextRenderer::ensureColorAtlasPage(std::uint32_t page) {
  while (m_colorAtlasPages.size() <= page) {
    GLuint tex = 0;
    glGenTextures(1, &tex);
    prepareAtlasUploadState();
    glBindTexture(GL_TEXTURE_2D, tex);
    std::vector<std::uint8_t> zeros(static_cast<size_t>(m_atlasWidth) * static_cast<size_t>(m_atlasHeight) * 4, 0);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, m_atlasWidth, m_atlasHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, zeros.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glGenerateMipmap(GL_TEXTURE_2D); // initial mipmaps for empty atlas (avoids "incomplete texture")
    m_colorAtlasPages.push_back(tex);
  }
  return m_colorAtlasPages[page];
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

// Shape a single run directly with one font slot — no fallback.
// Used for emoji runs routed to the dedicated color emoji slot.
void MsdfTextRenderer::shapeRunWithSlot(std::string_view run, std::uint32_t slotIndex,
                                         std::vector<ShapedGlyph>& out) {
  auto& slot = m_fontSlots[slotIndex];
  if (slot.hbFont == nullptr) {
    return;
  }

  hb_buffer_t* buf = hb_buffer_create();
  hb_buffer_add_utf8(buf, run.data(), static_cast<int>(run.size()), 0, static_cast<int>(run.size()));
  hb_buffer_guess_segment_properties(buf);
  hb_shape(slot.hbFont, buf, nullptr, 0);

  unsigned int cnt = 0;
  hb_glyph_info_t*     infos     = hb_buffer_get_glyph_infos(buf, &cnt);
  hb_glyph_position_t* positions = hb_buffer_get_glyph_positions(buf, &cnt);

  for (unsigned int i = 0; i < cnt; ++i) {
    out.push_back(ShapedGlyph{
        .key        = makeGlyphKey(slotIndex, infos[i].codepoint),
        .slotIndex  = slotIndex,
        .glyphIndex = infos[i].codepoint,
        .position   = positions[i],
    });
  }

  hb_buffer_destroy(buf);
}

// Shape a single text run with the primary font + per-notdef fallback.
// Skips m_emojiSlotIndex so emoji glyphs don't bleed into the text chain.
void MsdfTextRenderer::shapeRunWithFallback(std::string_view run, std::vector<ShapedGlyph>& out) {
  if (m_fontSlots.empty()) {
    return;
  }

  // Primary slot: slot 0, unless that IS the emoji slot (edge case).
  const std::uint32_t primarySlot = (m_emojiSlotIndex == 0 && m_fontSlots.size() > 1) ? 1u : 0u;

  hb_buffer_t* buffer = hb_buffer_create();
  hb_buffer_add_utf8(buffer, run.data(), static_cast<int>(run.size()), 0, static_cast<int>(run.size()));
  hb_buffer_guess_segment_properties(buffer);
  hb_shape(m_fontSlots[primarySlot].hbFont, buffer, nullptr, 0);

  unsigned int glyphCount = 0;
  hb_glyph_info_t*     glyphInfos     = hb_buffer_get_glyph_infos(buffer, &glyphCount);
  hb_glyph_position_t* glyphPositions = hb_buffer_get_glyph_positions(buffer, &glyphCount);

  std::vector<bool> needsFallback(glyphCount, false);
  bool anyNeedsFallback = false;
  const std::size_t resultStart = out.size();

  for (unsigned int i = 0; i < glyphCount; ++i) {
    out.push_back(ShapedGlyph{
        .key        = makeGlyphKey(primarySlot, glyphInfos[i].codepoint),
        .slotIndex  = primarySlot,
        .glyphIndex = glyphInfos[i].codepoint,
        .position   = glyphPositions[i],
    });
    if (glyphInfos[i].codepoint == 0) {
      needsFallback[i] = true;
      anyNeedsFallback = true;
    }
  }

  hb_buffer_destroy(buffer);

  if (!anyNeedsFallback || m_fontSlots.size() <= 1) {
    return;
  }

  // Re-shape to extract cluster byte offsets for per-notdef fallback.
  buffer = hb_buffer_create();
  hb_buffer_add_utf8(buffer, run.data(), static_cast<int>(run.size()), 0, static_cast<int>(run.size()));
  hb_buffer_guess_segment_properties(buffer);
  hb_shape(m_fontSlots[primarySlot].hbFont, buffer, nullptr, 0);
  glyphInfos = hb_buffer_get_glyph_infos(buffer, &glyphCount);

  for (unsigned int i = 0; i < glyphCount; ++i) {
    if (!needsFallback[i]) {
      continue;
    }

    const std::uint32_t clusterStart = glyphInfos[i].cluster;
    const std::uint32_t clusterEnd =
        (i + 1 < glyphCount) ? glyphInfos[i + 1].cluster : static_cast<std::uint32_t>(run.size());

    if (clusterEnd <= clusterStart) {
      continue; // RTL / complex ordering — skip
    }

    std::string_view cluster = run.substr(clusterStart, clusterEnd - clusterStart);

    for (std::uint32_t slotIdx = primarySlot + 1;
         slotIdx < static_cast<std::uint32_t>(m_fontSlots.size()); ++slotIdx) {
      if (slotIdx == m_emojiSlotIndex) {
        continue; // don't route text through the emoji slot
      }
      auto& slot = m_fontSlots[slotIdx];
      if (slot.hbFont == nullptr) {
        continue;
      }

      hb_buffer_t* fbBuf = hb_buffer_create();
      hb_buffer_add_utf8(fbBuf, cluster.data(), static_cast<int>(cluster.size()), 0,
                         static_cast<int>(cluster.size()));
      hb_buffer_guess_segment_properties(fbBuf);
      hb_shape(slot.hbFont, fbBuf, nullptr, 0);

      unsigned int fbCount = 0;
      hb_glyph_info_t*     fbInfos     = hb_buffer_get_glyph_infos(fbBuf, &fbCount);
      hb_glyph_position_t* fbPositions = hb_buffer_get_glyph_positions(fbBuf, &fbCount);

      if (fbCount >= 1 && fbInfos[0].codepoint != 0) {
        out[resultStart + i] = ShapedGlyph{
            .key        = makeGlyphKey(slotIdx, fbInfos[0].codepoint),
            .slotIndex  = slotIdx,
            .glyphIndex = fbInfos[0].codepoint,
            .position   = fbPositions[0],
        };
        hb_buffer_destroy(fbBuf);
        break;
      }
      hb_buffer_destroy(fbBuf);
    }
  }

  hb_buffer_destroy(buffer);
}

std::vector<MsdfTextRenderer::ShapedGlyph> MsdfTextRenderer::shapeWithFallback(std::string_view text,
                                                                                 float fontSize) {
  setShapingSize(fontSize);

  std::vector<ShapedGlyph> result;

  for (const auto& run : segmentEmojiRuns(text)) {
    std::string_view runText = text.substr(run.byteStart, run.byteEnd - run.byteStart);
    if (runText.empty()) {
      continue;
    }

    if (run.isEmoji && m_emojiSlotIndex < static_cast<std::uint32_t>(m_fontSlots.size())) {
      // Emoji run: shape directly with the color emoji font.
      // HarfBuzz handles ZWJ sequences, VS16, skin-tone modifiers, etc. correctly
      // when the whole sequence is passed to a single font that supports it.
      shapeRunWithSlot(runText, m_emojiSlotIndex, result);
    } else {
      // Text run: normal primary-font + per-notdef fallback, emoji slot excluded.
      shapeRunWithFallback(runText, result);
    }
  }

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

  // For color-capable fonts (CBDT, COLR v0/v1, sbix), try color rendering first.
  // This must come BEFORE msdfgen because COLR v0/v1 fonts have real vector
  // outlines — msdfgen would "succeed" and produce monochrome results for them.
  if (FT_HAS_COLOR(slot.face)) {
    FT_Set_Pixel_Sizes(slot.face, 0, static_cast<FT_UInt>(kColorAtlasEmSize));
    if (FT_Load_Glyph(slot.face, glyphIndex, FT_LOAD_COLOR | FT_LOAD_RENDER) == 0) {
      const FT_Bitmap& bm = slot.face->glyph->bitmap;
      if (bm.pixel_mode == FT_PIXEL_MODE_BGRA && bm.width > 0 && bm.rows > 0) {
        const int bw = static_cast<int>(bm.width);
        const int bh = static_cast<int>(bm.rows);

        // FT_PIXEL_MODE_BGRA is premultiplied. Reorder BGRA → RGBA for GL upload;
        // keep premultiplied to match the pipeline-wide GL_ONE / GL_ONE_MINUS_SRC_ALPHA blend.
        std::vector<unsigned char> rgba(static_cast<std::size_t>(bw * bh * 4));
        for (int row = 0; row < bh; ++row) {
          for (int col = 0; col < bw; ++col) {
            const unsigned char* src = bm.buffer + row * bm.pitch + col * 4;
            unsigned char* dst = rgba.data() + (row * bw + col) * 4;
            dst[0] = src[2]; // R (FT BGRA src[2])
            dst[1] = src[1]; // G
            dst[2] = src[0]; // B (FT BGRA src[0])
            dst[3] = src[3]; // A
          }
        }

        const int paddedW = bw + kGlyphPadding * 2;
        const int paddedH = bh + kGlyphPadding * 2;

        if (m_colorAtlasCursorX + paddedW > m_atlasWidth) {
          m_colorAtlasCursorX = 1;
          m_colorAtlasCursorY += m_colorAtlasRowHeight + 1;
          m_colorAtlasRowHeight = 0;
        }

        std::uint32_t colorPage =
            m_colorAtlasPages.empty() ? 0 : static_cast<std::uint32_t>(m_colorAtlasPages.size() - 1);

        if (m_colorAtlasCursorY + paddedH > m_atlasHeight) {
          colorPage = static_cast<std::uint32_t>(m_colorAtlasPages.size());
          ensureColorAtlasPage(colorPage);
          m_colorAtlasCursorX = 1;
          m_colorAtlasCursorY = 1;
          m_colorAtlasRowHeight = 0;
        } else {
          ensureColorAtlasPage(colorPage);
        }

        const int destX = m_colorAtlasCursorX + kGlyphPadding;
        const int destY = m_colorAtlasCursorY + kGlyphPadding;

        prepareAtlasUploadState();
        glBindTexture(GL_TEXTURE_2D, m_colorAtlasPages[colorPage]);
        glTexSubImage2D(GL_TEXTURE_2D, 0, destX, destY, bw, bh, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
        glGenerateMipmap(GL_TEXTURE_2D);

        const auto atlasW = static_cast<float>(m_atlasWidth);
        const auto atlasH = static_cast<float>(m_atlasHeight);
        // Normalize dimensions to kAtlasEmSize units so the existing scale = fontSize / kAtlasEmSize
        // formula in draw/measure produces the correct display size.
        constexpr float kColorNorm = kAtlasEmSize / kColorAtlasEmSize;

        Glyph colorGlyph{
            .atlasWidth  = static_cast<float>(bw)  * kColorNorm,
            .atlasHeight = static_cast<float>(bh)  * kColorNorm,
            .bearingX    = static_cast<float>(slot.face->glyph->bitmap_left)  * kColorNorm,
            .bearingY    = static_cast<float>(slot.face->glyph->bitmap_top)   * kColorNorm,
            .u0 = static_cast<float>(destX) / atlasW,
            .v0 = static_cast<float>(destY) / atlasH,
            .u1 = static_cast<float>(destX + bw) / atlasW,
            .v1 = static_cast<float>(destY + bh) / atlasH,
            .atlasPage = colorPage,
            .isColor = true,
        };

        m_colorAtlasCursorX += paddedW + 1;
        m_colorAtlasRowHeight = std::max(m_colorAtlasRowHeight, paddedH);

        // FT_Set_Pixel_Sizes changed this face's size; invalidate the
        // shaping size cache so the next draw re-sets it correctly.
        m_currentShapingSize = 0.0f;

        auto [it, _] = m_glyphs.emplace(key, colorGlyph);
        return it->second;
      }
    }
    // FT_LOAD_COLOR didn't produce a BGRA bitmap. For COLR v1 fonts FreeType has
    // no bitmap rasterizer — use Cairo which supports the COLR v1 paint engine.
    FT_OpaquePaint paint;
    paint.p = nullptr;
    if (FT_Get_Color_Glyph_Paint(slot.face, glyphIndex, FT_COLOR_NO_ROOT_TRANSFORM, &paint)) {
      if (slot.cairoFace == nullptr) {
        slot.cairoFace = cairo_ft_font_face_create_for_ft_face(slot.face, FT_LOAD_COLOR);
      }

      cairo_matrix_t fontMatrix;
      cairo_matrix_init_scale(&fontMatrix, kColorAtlasEmSize, kColorAtlasEmSize);
      cairo_matrix_t ctm;
      cairo_matrix_init_identity(&ctm);
      cairo_font_options_t* cairoOpts = cairo_font_options_create();
      cairo_scaled_font_t* sfont = cairo_scaled_font_create(slot.cairoFace, &fontMatrix, &ctm, cairoOpts);
      cairo_font_options_destroy(cairoOpts);

      cairo_glyph_t cglyph;
      cglyph.index = glyphIndex;
      cglyph.x     = 0.0;
      cglyph.y     = 0.0;
      cairo_text_extents_t ext{};
      cairo_scaled_font_glyph_extents(sfont, &cglyph, 1, &ext);

      const int cairoW = static_cast<int>(std::ceil(ext.width));
      const int cairoH = static_cast<int>(std::ceil(ext.height));

      if (cairoW > 0 && cairoH > 0) {
        cairo_surface_t* surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, cairoW, cairoH);
        cairo_t* cr = cairo_create(surf);
        cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.0);
        cairo_paint(cr);

        cglyph.x = -ext.x_bearing;
        cglyph.y = -ext.y_bearing;
        cairo_set_scaled_font(cr, sfont);
        cairo_show_glyphs(cr, &cglyph, 1);
        cairo_surface_flush(surf);

        // Cairo ARGB32 (little-endian): byte[0]=B, byte[1]=G, byte[2]=R, byte[3]=A (premultiplied).
        // Reorder to RGBA, keeping premultiplied to match GL_ONE/GL_ONE_MINUS_SRC_ALPHA blend.
        const unsigned char* srcData = cairo_image_surface_get_data(surf);
        const int cairoStride = cairo_image_surface_get_stride(surf);
        std::vector<unsigned char> rgba(static_cast<std::size_t>(cairoW * cairoH * 4));
        for (int row = 0; row < cairoH; ++row) {
          for (int col = 0; col < cairoW; ++col) {
            const unsigned char* src = srcData + row * cairoStride + col * 4;
            unsigned char* dst = rgba.data() + (row * cairoW + col) * 4;
            dst[0] = src[2]; // R
            dst[1] = src[1]; // G
            dst[2] = src[0]; // B
            dst[3] = src[3]; // A
          }
        }

        const int paddedW = cairoW + kGlyphPadding * 2;
        const int paddedH = cairoH + kGlyphPadding * 2;

        if (m_colorAtlasCursorX + paddedW > m_atlasWidth) {
          m_colorAtlasCursorX = 1;
          m_colorAtlasCursorY += m_colorAtlasRowHeight + 1;
          m_colorAtlasRowHeight = 0;
        }

        std::uint32_t colorPage =
            m_colorAtlasPages.empty() ? 0 : static_cast<std::uint32_t>(m_colorAtlasPages.size() - 1);

        if (m_colorAtlasCursorY + paddedH > m_atlasHeight) {
          colorPage = static_cast<std::uint32_t>(m_colorAtlasPages.size());
          ensureColorAtlasPage(colorPage);
          m_colorAtlasCursorX = 1;
          m_colorAtlasCursorY = 1;
          m_colorAtlasRowHeight = 0;
        } else {
          ensureColorAtlasPage(colorPage);
        }

        const int destX = m_colorAtlasCursorX + kGlyphPadding;
        const int destY = m_colorAtlasCursorY + kGlyphPadding;

        prepareAtlasUploadState();
        glBindTexture(GL_TEXTURE_2D, m_colorAtlasPages[colorPage]);
        glTexSubImage2D(GL_TEXTURE_2D, 0, destX, destY, cairoW, cairoH, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
        glGenerateMipmap(GL_TEXTURE_2D);

        const auto atlasW = static_cast<float>(m_atlasWidth);
        const auto atlasH = static_cast<float>(m_atlasHeight);
        // Normalize to kAtlasEmSize units so draw/measure scale = fontSize / kAtlasEmSize still works.
        constexpr float kColorNorm = kAtlasEmSize / kColorAtlasEmSize;

        Glyph colorGlyph{
            .atlasWidth  = static_cast<float>(cairoW) * kColorNorm,
            .atlasHeight = static_cast<float>(cairoH) * kColorNorm,
            .bearingX    = static_cast<float>(ext.x_bearing) * kColorNorm,
            .bearingY    = static_cast<float>(-ext.y_bearing) * kColorNorm, // Cairo y_bearing < 0 for above-baseline
            .u0 = static_cast<float>(destX) / atlasW,
            .v0 = static_cast<float>(destY) / atlasH,
            .u1 = static_cast<float>(destX + cairoW) / atlasW,
            .v1 = static_cast<float>(destY + cairoH) / atlasH,
            .atlasPage = colorPage,
            .isColor = true,
        };

        m_colorAtlasCursorX += paddedW + 1;
        m_colorAtlasRowHeight = std::max(m_colorAtlasRowHeight, paddedH);

        cairo_destroy(cr);
        cairo_surface_destroy(surf);
        cairo_scaled_font_destroy(sfont);

        m_currentShapingSize = 0.0f;
        auto [it, _] = m_glyphs.emplace(key, colorGlyph);
        return it->second;
      }

      cairo_scaled_font_destroy(sfont);
    }

    m_currentShapingSize = 0.0f; // pixel size changed; force reset before next shape call
  }

  msdfgen::Shape shape;
  double advance = 0.0;
  if (!msdfgen::loadGlyph(shape, slot.fontHandle, msdfgen::GlyphIndex(glyphIndex),
                          msdfgen::FONT_SCALING_EM_NORMALIZED, &advance)) {
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
    kLog.debug("allocated atlas page {}", currentPage);
  }

  const int destX = m_atlasCursorX + kGlyphPadding;
  const int destY = m_atlasCursorY + kGlyphPadding;

  prepareAtlasUploadState();
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
