#include "render/core/wuffs_image_decoder.h"

#include <cstring>
#include <utility>

#define WUFFS_IMPLEMENTATION
#include "wuffs-unsupported-snapshot.c"

namespace {

class RgbaDecodeCallbacks final : public wuffs_aux::DecodeImageCallbacks {
public:
  wuffs_base__pixel_format SelectPixfmt(
      const wuffs_base__image_config& imageConfig) override {
    (void)imageConfig;
    return wuffs_base__make_pixel_format(WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL);
  }
};

} // namespace

std::optional<DecodedRasterImage>
decodeRasterImage(const std::uint8_t* data, std::size_t size, std::string* errorMessage) {
  if ((data == nullptr) || (size == 0)) {
    if (errorMessage != nullptr) {
      *errorMessage = "empty image buffer";
    }
    return std::nullopt;
  }

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

