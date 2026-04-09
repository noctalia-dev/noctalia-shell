#pragma once

#include "render/core/color.h"
#include "render/core/mat3.h"

#include <GLES2/gl2.h>

#include <cstdint>
#include <list>
#include <string>
#include <string_view>
#include <unordered_map>

// Forward declarations to avoid dragging Pango headers into every TU.
typedef struct _PangoContext PangoContext;
typedef struct _PangoFontMap PangoFontMap;
typedef struct _PangoLayout PangoLayout;

class ColorGlyphProgram;

// Pango/Cairo-backed text renderer.
//
// Rasterizes a shaped PangoLayout into an ARGB32 Cairo surface, uploads it as
// a premultiplied RGBA texture, and draws it through ColorGlyphProgram.
// Handles Latin, CJK, Arabic, BiDi, and COLR v1 emoji via fontconfig fallback.
//
// measure() and truncate() do not require a current EGL context.
// draw() needs EGL current (creates/binds GL textures).
class CairoTextRenderer {
public:
  struct TextMetrics {
    float width = 0.0f;
    float left = 0.0f;
    float right = 0.0f;
    float top = 0.0f;    // negative — above baseline
    float bottom = 0.0f; // positive — below baseline
  };

  CairoTextRenderer();
  ~CairoTextRenderer();

  CairoTextRenderer(const CairoTextRenderer&) = delete;
  CairoTextRenderer& operator=(const CairoTextRenderer&) = delete;

  void initialize(ColorGlyphProgram* program);
  void cleanup();

  // HiDPI: raster at `scale × fontSize` pixels and shrink the quad by 1/scale.
  void setContentScale(float scale);

  [[nodiscard]] TextMetrics measure(std::string_view text, float fontSize, bool bold = false);

  void draw(float surfaceWidth, float surfaceHeight, float x, float baselineY, std::string_view text, float fontSize,
            const Color& color, const Mat3& transform, bool bold = false, float maxWidth = 0.0f);

private:
  struct CacheKey {
    std::string text;
    std::uint32_t sizeQ = 0;      // fontSize * 64 + 0.5
    std::uint32_t colorRgba = 0;  // packed r<<24|g<<16|b<<8|a
    std::uint32_t maxWidthQ = 0;  // maxWidth * 64 + 0.5, 0 = no limit
    std::uint16_t scaleQ = 0;     // contentScale * 64 + 0.5
    bool bold = false;

    bool operator==(const CacheKey& other) const noexcept;
  };
  struct CacheKeyHash {
    std::size_t operator()(const CacheKey& k) const noexcept;
  };

  // LruList is a list of pointers into map keys — we break the otherwise
  // circular type dependency (CacheEntry ↔ CacheMap) this way. CacheKey* is
  // stable because unordered_map never moves key-value nodes under insert
  // (we also reserve bucket capacity upfront to avoid rehashing).
  using LruList = std::list<const CacheKey*>;

  struct CacheEntry {
    GLuint texture = 0;
    int pixelWidth = 0;    // raster surface pixel width
    int pixelHeight = 0;   // raster surface pixel height
    float baselinePx = 0;  // baseline from top of surface, in raster pixels
    TextMetrics metrics;   // logical metrics in logical (unscaled) pixels
    std::size_t bytes = 0;
    LruList::iterator lruIt;
  };

  using CacheMap = std::unordered_map<CacheKey, CacheEntry, CacheKeyHash>;

  // Build a PangoLayout at the given scaled size. Caller owns the layout (g_object_unref).
  PangoLayout* buildLayout(std::string_view text, float fontSize, bool bold, float maxWidthPxScaled) const;
  // Render a layout into a new GL texture; fills out fields of `entry`.
  void rasterizeLayout(PangoLayout* layout, const Color& color, CacheEntry& entry);
  // Extract logical metrics from a laid-out PangoLayout, dividing by PANGO_SCALE and by scale.
  TextMetrics metricsFromLayout(PangoLayout* layout) const;

  CacheEntry* lookupOrRasterize(std::string_view text, float fontSize, bool bold, float maxWidth, const Color& color);
  void touch(CacheMap::iterator it);
  void evict(CacheMap::iterator it);
  void evictIfNeeded();

  static std::uint32_t packColor(const Color& c);

  float m_contentScale = 1.0f;

  PangoFontMap* m_fontMap = nullptr;    // not owned (default font map)
  PangoContext* m_pangoContext = nullptr; // owned
  ColorGlyphProgram* m_program = nullptr;

  CacheMap m_cache;
  LruList m_lru;
  std::size_t m_cacheBytes = 0;

  static constexpr std::size_t kMaxCacheEntries = 512;
  static constexpr std::size_t kMaxCacheBytes = 32 * 1024 * 1024;
};
