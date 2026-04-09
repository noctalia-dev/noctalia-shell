#include "render/text/cairo_text_renderer.h"

#include "core/log.h"
#include "render/programs/color_glyph_program.h"

#include <cairo.h>
#include <fontconfig/fontconfig.h>
#include <pango/pango.h>
#include <pango/pangocairo.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <functional>
#include <vector>

namespace {

constexpr Logger kLog("text");

constexpr std::uint32_t kSizeQuant = 64;
constexpr std::uint32_t kScaleQuant = 64;

inline std::uint32_t quantizeSize(float v) {
  return static_cast<std::uint32_t>(std::max(0.0f, v) * static_cast<float>(kSizeQuant) + 0.5f);
}

inline std::uint16_t quantizeScale(float v) {
  return static_cast<std::uint16_t>(std::max(0.0f, v) * static_cast<float>(kScaleQuant) + 0.5f);
}

void hashCombine(std::size_t& seed, std::size_t v) {
  seed ^= v + 0x9E3779B97F4A7C15ULL + (seed << 12) + (seed >> 4);
}

// Swap BGRA<->RGBA in place on a premultiplied ARGB32 Cairo surface buffer.
void swizzleBgraToRgba(unsigned char* data, int width, int height, int stride) {
  for (int y = 0; y < height; ++y) {
    unsigned char* row = data + y * stride;
    for (int x = 0; x < width; ++x) {
      unsigned char* p = row + x * 4;
      std::swap(p[0], p[2]); // B <-> R; G and A unchanged
    }
  }
}

} // namespace

// ── CacheKey equality/hash ──────────────────────────────────────────────────

bool CairoTextRenderer::CacheKey::operator==(const CacheKey& other) const noexcept {
  return bold == other.bold && sizeQ == other.sizeQ && colorRgba == other.colorRgba && scaleQ == other.scaleQ &&
         maxWidthQ == other.maxWidthQ && text == other.text;
}

std::size_t CairoTextRenderer::CacheKeyHash::operator()(const CacheKey& k) const noexcept {
  std::size_t seed = std::hash<std::string>{}(k.text);
  hashCombine(seed, std::hash<std::uint32_t>{}(k.sizeQ));
  hashCombine(seed, std::hash<std::uint32_t>{}(k.colorRgba));
  hashCombine(seed, std::hash<std::uint32_t>{}(k.maxWidthQ));
  hashCombine(seed, std::hash<std::uint16_t>{}(k.scaleQ));
  hashCombine(seed, std::hash<bool>{}(k.bold));
  return seed;
}

// ── Lifecycle ───────────────────────────────────────────────────────────────

CairoTextRenderer::CairoTextRenderer() = default;

CairoTextRenderer::~CairoTextRenderer() { cleanup(); }

void CairoTextRenderer::initialize(ColorGlyphProgram* program) {
  m_program = program;

  FcInit();

  if (cairo_version() < CAIRO_VERSION_ENCODE(1, 18, 0)) {
    kLog.warn("cairo version {} (<1.18) — COLR v1 color emoji will not render", cairo_version_string());
  }

  m_fontMap = pango_cairo_font_map_get_default(); // not owned
  m_pangoContext = pango_font_map_create_context(m_fontMap);

  // Force grayscale AA + full hinting + hinted metrics. Without this, Cairo
  // on an ARGB32 image surface produces unhinted glyph outlines that sample
  // off the pixel grid → noticeably blurrier than the old MSDF output. The
  // font options are applied on the shared PangoContext so both measure()
  // and draw() agree on glyph widths (critical — unhinted metrics produce
  // sub-pixel widths that differ from the hinted raster).
  cairo_font_options_t* fontOptions = cairo_font_options_create();
  cairo_font_options_set_antialias(fontOptions, CAIRO_ANTIALIAS_GRAY);
  cairo_font_options_set_hint_style(fontOptions, CAIRO_HINT_STYLE_FULL);
  cairo_font_options_set_hint_metrics(fontOptions, CAIRO_HINT_METRICS_ON);
  pango_cairo_context_set_font_options(m_pangoContext, fontOptions);
  cairo_font_options_destroy(fontOptions);

  // Reserve bucket count up front so CacheMap iterators remain stable for the
  // lifetime of every entry — we rely on that stability to keep LRU list
  // entries (which hold map iterators) valid.
  m_cache.max_load_factor(1.0f);
  m_cache.reserve(kMaxCacheEntries + 16);
}

void CairoTextRenderer::cleanup() {
  for (auto& [key, entry] : m_cache) {
    if (entry.texture != 0) {
      glDeleteTextures(1, &entry.texture);
    }
  }
  m_cache.clear();
  m_lru.clear();
  m_cacheBytes = 0;

  if (m_pangoContext != nullptr) {
    g_object_unref(m_pangoContext);
    m_pangoContext = nullptr;
  }
  m_fontMap = nullptr; // default map is not owned
  m_program = nullptr;
}

void CairoTextRenderer::setContentScale(float scale) {
  if (scale <= 0.0f) {
    return;
  }
  m_contentScale = scale;
}

// ── Layout construction ─────────────────────────────────────────────────────

PangoLayout* CairoTextRenderer::buildLayout(std::string_view text, float fontSize, bool bold,
                                            float maxWidthPxScaled) const {
  PangoLayout* layout = pango_layout_new(m_pangoContext);

  const float rasterSize = std::max(1.0f, fontSize * m_contentScale);
  PangoFontDescription* desc = pango_font_description_new();
  pango_font_description_set_family(desc, "sans-serif");
  pango_font_description_set_weight(desc, bold ? PANGO_WEIGHT_BOLD : PANGO_WEIGHT_NORMAL);
  pango_font_description_set_absolute_size(desc, static_cast<double>(rasterSize) * PANGO_SCALE);
  pango_layout_set_font_description(layout, desc);
  pango_font_description_free(desc);

  pango_layout_set_text(layout, text.data(), static_cast<int>(text.size()));

  if (maxWidthPxScaled > 0.0f) {
    pango_layout_set_width(layout, static_cast<int>(maxWidthPxScaled * PANGO_SCALE));
    pango_layout_set_ellipsize(layout, PANGO_ELLIPSIZE_END);
    pango_layout_set_single_paragraph_mode(layout, TRUE);
  } else {
    pango_layout_set_width(layout, -1);
  }

  return layout;
}

CairoTextRenderer::TextMetrics CairoTextRenderer::metricsFromLayout(PangoLayout* layout) const {
  PangoRectangle logical;
  pango_layout_get_extents(layout, nullptr, &logical);
  const int baselinePango = pango_layout_get_baseline(layout);

  const float invScale = 1.0f / m_contentScale;
  const float pscale = 1.0f / static_cast<float>(PANGO_SCALE);

  const float width = static_cast<float>(logical.width) * pscale * invScale;
  // Pango logical rect y is 0 at top of layout box; baseline is offset from top.
  const float ascent = static_cast<float>(baselinePango - logical.y) * pscale * invScale;
  const float descent = static_cast<float>(logical.height - (baselinePango - logical.y)) * pscale * invScale;

  TextMetrics m;
  m.width = width;
  m.left = 0.0f;
  m.right = width;
  m.top = -ascent;    // above baseline → negative
  m.bottom = descent; // below baseline → positive
  return m;
}

// ── measure / truncate ──────────────────────────────────────────────────────

CairoTextRenderer::TextMetrics CairoTextRenderer::measure(std::string_view text, float fontSize, bool bold) {
  if (m_pangoContext == nullptr || text.empty()) {
    return {};
  }

  PangoLayout* layout = buildLayout(text, fontSize, bold, 0.0f);
  const auto metrics = metricsFromLayout(layout);
  g_object_unref(layout);
  return metrics;
}

// ── Rasterization ───────────────────────────────────────────────────────────

void CairoTextRenderer::rasterizeLayout(PangoLayout* layout, const Color& color, CacheEntry& entry) {
  // Pixel-sized surface: ceil the logical rect up.
  int pxWidth = 0;
  int pxHeight = 0;
  pango_layout_get_pixel_size(layout, &pxWidth, &pxHeight);

  // Guard against zero-sized surfaces Cairo rejects.
  pxWidth = std::max(1, pxWidth);
  pxHeight = std::max(1, pxHeight);

  // Baseline from top of layout, in raster pixels.
  const int baselinePango = pango_layout_get_baseline(layout);
  entry.baselinePx = static_cast<float>(baselinePango) / static_cast<float>(PANGO_SCALE);
  entry.pixelWidth = pxWidth;
  entry.pixelHeight = pxHeight;

  cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, pxWidth, pxHeight);
  cairo_t* cr = cairo_create(surface);
  cairo_set_operator(cr, CAIRO_OPERATOR_CLEAR);
  cairo_paint(cr);
  cairo_set_operator(cr, CAIRO_OPERATOR_OVER);
  cairo_set_source_rgba(cr, color.r, color.g, color.b, color.a);
  pango_cairo_show_layout(cr, layout);
  cairo_destroy(cr);
  cairo_surface_flush(surface);

  const int stride = cairo_image_surface_get_stride(surface);
  unsigned char* data = cairo_image_surface_get_data(surface);
  swizzleBgraToRgba(data, pxWidth, pxHeight, stride);

  // Upload. ARGB32 stride may include row padding: GL_UNPACK_ROW_LENGTH is a
  // GLES3 feature, so we repack the rows tightly for the texture.
  const int tightRowBytes = pxWidth * 4;
  std::vector<unsigned char> tight(static_cast<std::size_t>(tightRowBytes) * static_cast<std::size_t>(pxHeight));
  for (int y = 0; y < pxHeight; ++y) {
    std::memcpy(tight.data() + y * tightRowBytes, data + y * stride, static_cast<std::size_t>(tightRowBytes));
  }
  cairo_surface_destroy(surface);

  GLuint tex = 0;
  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, pxWidth, pxHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, tight.data());
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  entry.texture = tex;
  entry.bytes = static_cast<std::size_t>(tightRowBytes) * static_cast<std::size_t>(pxHeight);
  entry.metrics = metricsFromLayout(layout);
}

// ── Cache management ────────────────────────────────────────────────────────

std::uint32_t CairoTextRenderer::packColor(const Color& c) {
  const auto clamp8 = [](float v) -> std::uint32_t {
    const float s = std::clamp(v, 0.0f, 1.0f);
    return static_cast<std::uint32_t>(s * 255.0f + 0.5f);
  };
  return (clamp8(c.r) << 24) | (clamp8(c.g) << 16) | (clamp8(c.b) << 8) | clamp8(c.a);
}

void CairoTextRenderer::touch(CacheMap::iterator it) {
  // Splice the LRU node to the front (most-recently-used).
  m_lru.splice(m_lru.begin(), m_lru, it->second.lruIt);
}

void CairoTextRenderer::evict(CacheMap::iterator it) {
  if (it->second.texture != 0) {
    glDeleteTextures(1, &it->second.texture);
  }
  m_cacheBytes -= it->second.bytes;
  m_lru.erase(it->second.lruIt);
  m_cache.erase(it);
}

void CairoTextRenderer::evictIfNeeded() {
  while (!m_lru.empty() && (m_cache.size() > kMaxCacheEntries || m_cacheBytes > kMaxCacheBytes)) {
    const CacheKey* keyPtr = m_lru.back();
    auto mapIt = m_cache.find(*keyPtr);
    if (mapIt == m_cache.end()) {
      m_lru.pop_back();
      continue;
    }
    evict(mapIt);
  }
}

CairoTextRenderer::CacheEntry* CairoTextRenderer::lookupOrRasterize(std::string_view text, float fontSize, bool bold,
                                                                    float maxWidth, const Color& color) {
  CacheKey key;
  key.text.assign(text);
  key.sizeQ = quantizeSize(fontSize);
  key.colorRgba = packColor(color);
  key.maxWidthQ = quantizeSize(std::max(0.0f, maxWidth));
  key.scaleQ = quantizeScale(m_contentScale);
  key.bold = bold;

  auto it = m_cache.find(key);
  if (it != m_cache.end()) {
    touch(it);
    return &it->second;
  }

  PangoLayout* layout = buildLayout(text, fontSize, bold, maxWidth * m_contentScale);
  CacheEntry entry{};
  rasterizeLayout(layout, color, entry);
  g_object_unref(layout);

  auto [ins, inserted] = m_cache.emplace(std::move(key), std::move(entry));
  m_lru.push_front(&ins->first);
  ins->second.lruIt = m_lru.begin();
  m_cacheBytes += ins->second.bytes;

  evictIfNeeded();
  return &ins->second;
}

// ── draw ────────────────────────────────────────────────────────────────────

void CairoTextRenderer::draw(float surfaceWidth, float surfaceHeight, float x, float baselineY, std::string_view text,
                             float fontSize, const Color& color, const Mat3& transform, bool bold, float maxWidth) {
  if (m_pangoContext == nullptr || m_program == nullptr || text.empty()) {
    return;
  }

  CacheEntry* entry = lookupOrRasterize(text, fontSize, bold, maxWidth, color);
  if (entry == nullptr || entry->texture == 0) {
    return;
  }

  const float invScale = 1.0f / m_contentScale;
  const float quadW = static_cast<float>(entry->pixelWidth) * invScale;
  const float quadH = static_cast<float>(entry->pixelHeight) * invScale;
  const float baselineLocal = entry->baselinePx * invScale;

  // Translate the quad so that `baselineY` (local) lines up with the raster
  // surface's baseline row. With baselineY=0 (callers using Label), the surface
  // is shifted up by `baselineLocal`, placing the baseline at local y=0.
  const Mat3 localTranslation = Mat3::translation(x, baselineY - baselineLocal);
  Mat3 world = transform * localTranslation;

  // Snap the glyph quad's origin to the nearest buffer pixel. Without this,
  // fractional layout positions place the quad at sub-pixel offsets and
  // GL_LINEAR samples across texel boundaries → noticeable blur even at 1x.
  // Snap in buffer-pixel space so HiDPI outputs still benefit.
  //
  // Only snap when the transform is axis-aligned (no rotation/skew). During
  // a rotation animation, snapping causes the translation to jump by whole
  // buffer pixels between frames, which looks jittery on 1x outputs.
  const bool axisAligned = world.m[1] == 0.0f && world.m[3] == 0.0f;
  if (axisAligned) {
    world.m[6] = std::round(world.m[6] * m_contentScale) / m_contentScale;
    world.m[7] = std::round(world.m[7] * m_contentScale) / m_contentScale;
  }

  m_program->draw(entry->texture, surfaceWidth, surfaceHeight, quadW, quadH, 0.0f, 0.0f, 1.0f, 1.0f, 1.0f, world);
}
