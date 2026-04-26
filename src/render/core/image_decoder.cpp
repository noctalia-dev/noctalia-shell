#include "render/core/image_decoder.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <utility>
#include <vector>
#include <webp/decode.h>

#define WUFFS_IMPLEMENTATION
#include "wuffs-v0.4.c"

namespace {

  class RgbaDecodeCallbacks final : public wuffs_aux::DecodeImageCallbacks {
  public:
    wuffs_base__pixel_format SelectPixfmt(const wuffs_base__image_config& imageConfig) override {
      (void)imageConfig;
      return wuffs_base__make_pixel_format(WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL);
    }
  };

  // Returns true if the buffer starts with the RIFF....WEBP signature.
  bool isWebP(const std::uint8_t* data, std::size_t size) {
    return size >= 12 && data[0] == 'R' && data[1] == 'I' && data[2] == 'F' && data[3] == 'F' && data[8] == 'W' &&
           data[9] == 'E' && data[10] == 'B' && data[11] == 'P';
  }

  std::optional<DecodedRasterImage> decodeWebP(const std::uint8_t* data, std::size_t size, std::string* errorMessage) {
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

std::optional<DecodedRasterImage> decodeRasterImage(const std::uint8_t* data, std::size_t size,
                                                    std::string* errorMessage) {
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

namespace {

  bool isGif(const std::uint8_t* data, std::size_t size) {
    return size >= 6 && data[0] == 'G' && data[1] == 'I' && data[2] == 'F' && data[3] == '8' &&
           (data[4] == '7' || data[4] == '9') && data[5] == 'a';
  }

  // GIF disposal applied to the persistent canvas BEFORE drawing the next
  // frame, given the previous frame's disposal code and bounds.
  void applyDisposal(std::uint8_t* canvas, int canvasWidth, int canvasHeight, wuffs_base__animation_disposal disposal,
                     wuffs_base__rect_ie_u32 bounds, const std::uint8_t* previous) {
    if (disposal == WUFFS_BASE__ANIMATION_DISPOSAL__NONE) {
      return;
    }
    const std::uint32_t x0 = std::min<std::uint32_t>(bounds.min_incl_x, static_cast<std::uint32_t>(canvasWidth));
    const std::uint32_t y0 = std::min<std::uint32_t>(bounds.min_incl_y, static_cast<std::uint32_t>(canvasHeight));
    const std::uint32_t x1 = std::min<std::uint32_t>(bounds.max_excl_x, static_cast<std::uint32_t>(canvasWidth));
    const std::uint32_t y1 = std::min<std::uint32_t>(bounds.max_excl_y, static_cast<std::uint32_t>(canvasHeight));
    if (x1 <= x0 || y1 <= y0) {
      return;
    }
    const std::size_t stride = static_cast<std::size_t>(canvasWidth) * 4;
    const std::size_t rowBytes = static_cast<std::size_t>(x1 - x0) * 4;
    if (disposal == WUFFS_BASE__ANIMATION_DISPOSAL__RESTORE_BACKGROUND) {
      for (std::uint32_t y = y0; y < y1; ++y) {
        std::memset(canvas + y * stride + x0 * 4, 0, rowBytes);
      }
    } else if (disposal == WUFFS_BASE__ANIMATION_DISPOSAL__RESTORE_PREVIOUS && previous != nullptr) {
      for (std::uint32_t y = y0; y < y1; ++y) {
        std::memcpy(canvas + y * stride + x0 * 4, previous + y * stride + x0 * 4, rowBytes);
      }
    }
  }

  std::uint32_t clampGifDurationMs(wuffs_base__flicks duration) {
    constexpr std::int64_t kFlicksPerSecond = WUFFS_BASE__FLICKS_PER_SECOND;
    const std::int64_t ms = (static_cast<std::int64_t>(duration) * 1000) / kFlicksPerSecond;
    if (ms < 10) {
      return 100; // browsers' rule for "0 / ASAP" GIFs
    }
    return static_cast<std::uint32_t>(ms);
  }

} // namespace

std::optional<DecodedRasterAnimation> decodeAnimatedGif(const std::uint8_t* data, std::size_t size, int maxFrames,
                                                        std::size_t maxRgbaBytes, std::string* errorMessage) {
  auto fail = [&](const char* msg) -> std::optional<DecodedRasterAnimation> {
    if (errorMessage != nullptr) {
      *errorMessage = msg;
    }
    return std::nullopt;
  };

  if (data == nullptr || size == 0) {
    return fail("empty image buffer");
  }
  if (!isGif(data, size)) {
    return fail("not a GIF");
  }

  auto dec = wuffs_gif__decoder::alloc_as__wuffs_base__image_decoder();
  if (!dec) {
    return fail("failed to allocate GIF decoder");
  }

  wuffs_base__io_buffer io = wuffs_base__ptr_u8__reader(const_cast<std::uint8_t*>(data), size, /*closed=*/true);

  wuffs_base__image_config imgcfg{};
  {
    wuffs_base__status st = dec->decode_image_config(&imgcfg, &io);
    if (st.repr != nullptr) {
      return fail(st.repr);
    }
  }

  const std::uint32_t width = wuffs_base__pixel_config__width(&imgcfg.pixcfg);
  const std::uint32_t height = wuffs_base__pixel_config__height(&imgcfg.pixcfg);
  if (width == 0 || height == 0) {
    return fail("GIF has zero dimensions");
  }
  const std::uint64_t canvasBytes64 = static_cast<std::uint64_t>(width) * height * 4;
  if (canvasBytes64 > maxRgbaBytes) {
    return fail("GIF canvas exceeds size cap");
  }
  const std::size_t canvasBytes = static_cast<std::size_t>(canvasBytes64);

  wuffs_base__pixel_config pixcfg{};
  wuffs_base__pixel_config__set(&pixcfg, WUFFS_BASE__PIXEL_FORMAT__RGBA_NONPREMUL, WUFFS_BASE__PIXEL_SUBSAMPLING__NONE,
                                width, height);

  std::vector<std::uint8_t> canvas(canvasBytes, 0);
  std::vector<std::uint8_t> previous; // lazy-allocated only if a RESTORE_PREVIOUS frame appears

  wuffs_base__pixel_buffer pb{};
  {
    wuffs_base__status st =
        wuffs_base__pixel_buffer__set_from_slice(&pb, &pixcfg, wuffs_base__make_slice_u8(canvas.data(), canvasBytes));
    if (st.repr != nullptr) {
      return fail(st.repr);
    }
  }

  const std::uint64_t workbufLen = dec->workbuf_len().max_incl;
  std::vector<std::uint8_t> workbuf(static_cast<std::size_t>(workbufLen));
  wuffs_base__slice_u8 workbufSlice = wuffs_base__make_slice_u8(workbuf.data(), workbuf.size());

  DecodedRasterAnimation result;
  result.width = static_cast<int>(width);
  result.height = static_cast<int>(height);

  wuffs_base__animation_disposal prevDisposal = WUFFS_BASE__ANIMATION_DISPOSAL__NONE;
  wuffs_base__rect_ie_u32 prevBounds = wuffs_base__empty_rect_ie_u32();
  std::size_t cumulativeBytes = 0;

  while (true) {
    wuffs_base__frame_config fc{};
    wuffs_base__status fcStatus = dec->decode_frame_config(&fc, &io);
    if (fcStatus.repr == wuffs_base__note__end_of_data) {
      break;
    }
    if (fcStatus.repr != nullptr) {
      if (result.frames.empty()) {
        return fail(fcStatus.repr);
      }
      // Tolerate trailing decode noise after we already have valid frames.
      break;
    }

    applyDisposal(canvas.data(), static_cast<int>(width), static_cast<int>(height), prevDisposal, prevBounds,
                  previous.empty() ? nullptr : previous.data());

    const wuffs_base__animation_disposal currentDisposal = fc.disposal();
    if (currentDisposal == WUFFS_BASE__ANIMATION_DISPOSAL__RESTORE_PREVIOUS) {
      if (previous.size() != canvasBytes) {
        previous.assign(canvasBytes, 0);
      }
      std::memcpy(previous.data(), canvas.data(), canvasBytes);
    }

    const wuffs_base__pixel_blend blend =
        fc.overwrite_instead_of_blend() ? WUFFS_BASE__PIXEL_BLEND__SRC : WUFFS_BASE__PIXEL_BLEND__SRC_OVER;

    wuffs_base__status frameStatus = dec->decode_frame(&pb, &io, blend, workbufSlice, nullptr);
    if (frameStatus.repr != nullptr && frameStatus.repr != wuffs_base__note__end_of_data) {
      if (result.frames.empty()) {
        return fail(frameStatus.repr);
      }
      break;
    }

    DecodedRasterFrame frame;
    frame.rgba.assign(canvas.begin(), canvas.end());
    frame.durationMs = clampGifDurationMs(fc.duration());
    cumulativeBytes += canvasBytes;
    result.frames.push_back(std::move(frame));

    prevDisposal = currentDisposal;
    prevBounds = fc.bounds();

    if (static_cast<int>(result.frames.size()) >= maxFrames || cumulativeBytes >= maxRgbaBytes) {
      result.truncated = true;
      break;
    }

    if (frameStatus.repr == wuffs_base__note__end_of_data) {
      break;
    }
  }

  if (result.frames.empty()) {
    return fail("GIF produced no frames");
  }
  return result;
}
