#include "render/core/image_file_loader.h"

#include "render/core/image_decoder.h"
#include "util/file_utils.h"

#include <algorithm>
#include <cairo.h>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <librsvg/rsvg.h>

namespace {

  // Convert a cairo ARGB32 image surface (premultiplied BGRA on little-endian)
  // into the non-premultiplied RGBA buffer the rest of the pipeline expects.
  void argb32ToRgba(const unsigned char* src, int srcStride, std::uint8_t* dst, int width, int height) {
    for (int y = 0; y < height; ++y) {
      const std::uint32_t* row = reinterpret_cast<const std::uint32_t*>(src + (y * srcStride));
      std::uint8_t* outRow = dst + (static_cast<std::size_t>(y) * static_cast<std::size_t>(width) * 4U);
      for (int x = 0; x < width; ++x) {
        const std::uint32_t pixel = row[x];
        const std::uint8_t a = static_cast<std::uint8_t>((pixel >> 24) & 0xFF);
        std::uint8_t r = static_cast<std::uint8_t>((pixel >> 16) & 0xFF);
        std::uint8_t g = static_cast<std::uint8_t>((pixel >> 8) & 0xFF);
        std::uint8_t b = static_cast<std::uint8_t>(pixel & 0xFF);
        if (a != 0 && a != 255) {
          // Un-premultiply, rounding to nearest.
          r = static_cast<std::uint8_t>(std::min(255, ((r * 255) + (a / 2)) / a));
          g = static_cast<std::uint8_t>(std::min(255, ((g * 255) + (a / 2)) / a));
          b = static_cast<std::uint8_t>(std::min(255, ((b * 255) + (a / 2)) / a));
        }
        outRow[(x * 4) + 0] = r;
        outRow[(x * 4) + 1] = g;
        outRow[(x * 4) + 2] = b;
        outRow[(x * 4) + 3] = a;
      }
    }
  }

  std::optional<LoadedImageFile> rasterizeSvg(const std::vector<std::uint8_t>& fileData, int targetSize,
                                              std::string* errorMessage) {
    GError* gerror = nullptr;
    RsvgHandle* handle = rsvg_handle_new_from_data(fileData.data(), fileData.size(), &gerror);
    if (handle == nullptr) {
      if (errorMessage != nullptr) {
        *errorMessage = std::string("failed to parse SVG: ") + (gerror != nullptr ? gerror->message : "unknown");
      }
      if (gerror != nullptr) {
        g_error_free(gerror);
      }
      return std::nullopt;
    }

    // Determine intrinsic pixel size. Many real-world SVGs (e.g. viewBox-only)
    // do not advertise pixel dimensions, so fall back to the viewBox or to a
    // sensible default before computing the render scale.
    gdouble intrinsicW = 0.0;
    gdouble intrinsicH = 0.0;
    gboolean hasIntrinsic = rsvg_handle_get_intrinsic_size_in_pixels(handle, &intrinsicW, &intrinsicH);
    if (hasIntrinsic == FALSE || intrinsicW <= 0.0 || intrinsicH <= 0.0) {
      gboolean outHasW = FALSE;
      RsvgLength outW{};
      gboolean outHasH = FALSE;
      RsvgLength outH{};
      gboolean outHasViewbox = FALSE;
      RsvgRectangle outViewbox{};
      rsvg_handle_get_intrinsic_dimensions(handle, &outHasW, &outW, &outHasH, &outH, &outHasViewbox, &outViewbox);
      if (outHasViewbox == TRUE && outViewbox.width > 0.0 && outViewbox.height > 0.0) {
        intrinsicW = outViewbox.width;
        intrinsicH = outViewbox.height;
      } else {
        intrinsicW = 512.0;
        intrinsicH = 512.0;
      }
    }

    int width = static_cast<int>(std::round(intrinsicW));
    int height = static_cast<int>(std::round(intrinsicH));
    if (targetSize > 0) {
      const double maxSide = std::max(intrinsicW, intrinsicH);
      const double scale = static_cast<double>(targetSize) / maxSide;
      width = std::max(1, static_cast<int>(std::round(intrinsicW * scale)));
      height = std::max(1, static_cast<int>(std::round(intrinsicH * scale)));
    }
    if (width <= 0 || height <= 0) {
      if (errorMessage != nullptr) {
        *errorMessage = "invalid SVG dimensions";
      }
      g_object_unref(handle);
      return std::nullopt;
    }

    cairo_surface_t* surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width, height);
    if (cairo_surface_status(surface) != CAIRO_STATUS_SUCCESS) {
      if (errorMessage != nullptr) {
        *errorMessage = "failed to create cairo surface";
      }
      cairo_surface_destroy(surface);
      g_object_unref(handle);
      return std::nullopt;
    }

    cairo_t* cr = cairo_create(surface);
    RsvgRectangle viewport{
        .x = 0.0,
        .y = 0.0,
        .width = static_cast<double>(width),
        .height = static_cast<double>(height),
    };
    GError* renderError = nullptr;
    if (rsvg_handle_render_document(handle, cr, &viewport, &renderError) == FALSE) {
      if (errorMessage != nullptr) {
        *errorMessage =
            std::string("failed to render SVG: ") + (renderError != nullptr ? renderError->message : "unknown");
      }
      if (renderError != nullptr) {
        g_error_free(renderError);
      }
      cairo_destroy(cr);
      cairo_surface_destroy(surface);
      g_object_unref(handle);
      return std::nullopt;
    }
    cairo_destroy(cr);
    cairo_surface_flush(surface);

    LoadedImageFile loaded{
        .rgba = std::vector<std::uint8_t>(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U),
        .width = width,
        .height = height,
    };
    argb32ToRgba(cairo_image_surface_get_data(surface), cairo_image_surface_get_stride(surface), loaded.rgba.data(),
                 width, height);

    cairo_surface_destroy(surface);
    g_object_unref(handle);
    return loaded;
  }

} // namespace

std::optional<LoadedImageFile> loadImageFile(const std::string& path, int targetSize, std::string* errorMessage) {
  if (path.empty()) {
    if (errorMessage != nullptr) {
      *errorMessage = "empty image path";
    }
    return std::nullopt;
  }

  auto fileData = FileUtils::readBinaryFile(path);
  if (fileData.empty()) {
    if (errorMessage != nullptr) {
      *errorMessage = "failed to read image file";
    }
    return std::nullopt;
  }

  if (path.ends_with(".svg") || path.ends_with(".SVG")) {
    return rasterizeSvg(fileData, targetSize, errorMessage);
  }

  if (auto decoded = decodeRasterImage(fileData.data(), fileData.size(), errorMessage)) {
    return LoadedImageFile{.rgba = std::move(decoded->pixels), .width = decoded->width, .height = decoded->height};
  }

  return std::nullopt;
}
