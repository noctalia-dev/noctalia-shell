#include "render/core/image_decoder.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <utility>

#include <webp/decode.h>

#define WUFFS_IMPLEMENTATION
#include "wuffs-v0.4.c"

namespace {

class RgbaDecodeCallbacks final : public wuffs_aux::DecodeImageCallbacks {
public:
  wuffs_base__pixel_format SelectPixfmt(
      const wuffs_base__image_config& imageConfig) override {
    (void)imageConfig;
    return wuffs_base__make_pixel_format(WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL);
  }
};

// Returns true if the buffer starts with the RIFF....WEBP signature.
bool isWebP(const std::uint8_t* data, std::size_t size) {
  return size >= 12 &&
         data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' &&
         data[8] == 'W' && data[9] == 'E' && data[10] == 'B' && data[11] == 'P';
}

std::optional<DecodedRasterImage> decodeWebP(
    const std::uint8_t* data, std::size_t size, std::string* errorMessage) {
  int width = 0, height = 0;
  std::uint8_t* rgba = WebPDecodeRGBA(data, size, &width, &height);
  if (rgba == nullptr) {
    if (errorMessage != nullptr)
      *errorMessage = "libwebp: failed to decode WebP image";
    return std::nullopt;
  }

  DecodedRasterImage decoded;
  decoded.width = width;
  decoded.height = height;
  std::size_t bytes = static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4;
  decoded.pixels.resize(bytes);
  std::memcpy(decoded.pixels.data(), rgba, bytes);
  WebPFree(rgba);
  return decoded;
}

} // namespace

std::optional<DecodedRasterImage>
decodeRasterImage(const std::uint8_t* data, std::size_t size, std::string* errorMessage) {
  if ((data == nullptr) || (size == 0)) {
    if (errorMessage != nullptr) {
      *errorMessage = "empty image buffer";
    }
    return std::nullopt;
  }

  if (isWebP(data, size))
    return decodeWebP(data, size, errorMessage);

  auto input = wuffs_aux::sync_io::MemoryInput(data, size);
  auto callbacks = RgbaDecodeCallbacks();
  auto result = wuffs_aux::DecodeImage(callbacks, input);
  if (!result.error_message.empty()) {
    if (errorMessage != nullptr) {
      *errorMessage = result.error_message;
    }
    return std::nullopt;
  }

  auto plane = result.pixbuf.plane(0);
  if ((plane.ptr == nullptr) || (plane.width == 0) || (plane.height == 0)) {
    if (errorMessage != nullptr) {
      *errorMessage = "decoded image has no pixel data";
    }
    return std::nullopt;
  }

  DecodedRasterImage decoded;
  decoded.width = static_cast<int>(result.pixbuf.pixcfg.width());
  decoded.height = static_cast<int>(result.pixbuf.pixcfg.height());
  decoded.pixels.resize(plane.width * plane.height);
  std::memcpy(decoded.pixels.data(), plane.ptr, decoded.pixels.size());
  return decoded;
}
