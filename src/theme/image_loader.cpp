#include "theme/image_loader.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>

#include "render/core/image_decoder.h"

namespace noctalia::theme {

  namespace {

    constexpr int kTarget = 112;

    std::vector<uint8_t> readFile(std::string_view path, std::string* err) {
      std::ifstream f(std::string(path), std::ios::binary);
      if (!f) {
        if (err)
          *err = "cannot open file";
        return {};
      }
      return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    }

    // Hand-port of `image::imageops::sample::resize` (Triangle filter) from
    // the Rust `image` crate, which is what matugen / material_colors uses.
    // We need byte-for-byte parity with that implementation because a few
    // LSB of drift in the resized 112×112 buffer can move the seed to a
    // different cluster.
    //
    // Algorithm: separable scale-aware tent filter, vertical pass first
    // into a float intermediate (no clamping/rounding between passes), then
    // horizontal pass with clamp+round-to-nearest into u8. For downsampling
    // the kernel support widens by the downsample ratio. Operates in 8-bit
    // sRGB space (no linearisation), matching image crate.
    //
    // Pixel-center convention: input pixels are at integer positions; the
    // output pixel `o` corresponds to input center `(o + 0.5) * ratio`. The
    // kernel is evaluated at `(i - (inputCenter - 0.5)) / sratio` for input
    // pixel index `i`. See sample.rs in the image crate for the canonical
    // form.
    inline float triangleKernel(float x) {
      x = x < 0 ? -x : x;
      return x < 1.0f ? 1.0f - x : 0.0f;
    }

    // Vertical pass: src is RGBA u8 (srcW × srcH), dst is RGBA f32 (srcW × dstH).
    void verticalSampleU8ToF32(const uint8_t* src, int srcW, int srcH, float* dst, int dstH) {
      const float ratio = (float)srcH / (float)dstH;
      const float sratio = ratio < 1.0f ? 1.0f : ratio;
      const float srcSupport = 1.0f * sratio;

      std::vector<float> ws;
      for (int outy = 0; outy < dstH; ++outy) {
        const float inputyOrig = ((float)outy + 0.5f) * ratio;
        int left = (int)std::floor(inputyOrig - srcSupport);
        int right = (int)std::ceil(inputyOrig + srcSupport);
        if (left < 0)
          left = 0;
        if (left > srcH - 1)
          left = srcH - 1;
        if (right < left + 1)
          right = left + 1;
        if (right > srcH)
          right = srcH;
        const float inputy = inputyOrig - 0.5f;

        ws.clear();
        float sum = 0.0f;
        for (int i = left; i < right; ++i) {
          float w = triangleKernel(((float)i - inputy) / sratio);
          ws.push_back(w);
          sum += w;
        }
        for (auto& w : ws)
          w /= sum;

        for (int x = 0; x < srcW; ++x) {
          float t0 = 0, t1 = 0, t2 = 0, t3 = 0;
          for (int k = 0; k < (int)ws.size(); ++k) {
            const uint8_t* p = src + ((left + k) * srcW + x) * 4;
            const float w = ws[k];
            t0 += (float)p[0] * w;
            t1 += (float)p[1] * w;
            t2 += (float)p[2] * w;
            t3 += (float)p[3] * w;
          }
          float* dp = dst + (outy * srcW + x) * 4;
          // No clamp / no round — image crate's vertical_sample writes raw
          // f32 into Rgba32FImage.
          dp[0] = t0;
          dp[1] = t1;
          dp[2] = t2;
          dp[3] = t3;
        }
      }
    }

    // Horizontal pass: src is RGBA f32 (srcW × srcH), dst is RGBA u8 (dstW × srcH).
    void horizontalSampleF32ToU8(const float* src, int srcW, int srcH, uint8_t* dst, int dstW) {
      const float ratio = (float)srcW / (float)dstW;
      const float sratio = ratio < 1.0f ? 1.0f : ratio;
      const float srcSupport = 1.0f * sratio;

      std::vector<float> ws;
      for (int outx = 0; outx < dstW; ++outx) {
        const float inputxOrig = ((float)outx + 0.5f) * ratio;
        int left = (int)std::floor(inputxOrig - srcSupport);
        int right = (int)std::ceil(inputxOrig + srcSupport);
        if (left < 0)
          left = 0;
        if (left > srcW - 1)
          left = srcW - 1;
        if (right < left + 1)
          right = left + 1;
        if (right > srcW)
          right = srcW;
        const float inputx = inputxOrig - 0.5f;

        ws.clear();
        float sum = 0.0f;
        for (int i = left; i < right; ++i) {
          float w = triangleKernel(((float)i - inputx) / sratio);
          ws.push_back(w);
          sum += w;
        }
        for (auto& w : ws)
          w /= sum;

        for (int y = 0; y < srcH; ++y) {
          float t0 = 0, t1 = 0, t2 = 0, t3 = 0;
          for (int k = 0; k < (int)ws.size(); ++k) {
            const float* p = src + (y * srcW + (left + k)) * 4;
            const float w = ws[k];
            t0 += p[0] * w;
            t1 += p[1] * w;
            t2 += p[2] * w;
            t3 += p[3] * w;
          }
          // FloatNearest(clamp(t, 0, 255)) → u8. Rust's f32::round is
          // round-half-away-from-zero.
          auto toU8 = [](float v) -> uint8_t {
            if (v < 0)
              v = 0;
            if (v > 255)
              v = 255;
            float r = v < 0.0f ? std::ceil(v - 0.5f) : std::floor(v + 0.5f);
            return (uint8_t)r;
          };
          uint8_t* dp = dst + (y * dstW + outx) * 4;
          dp[0] = toU8(t0);
          dp[1] = toU8(t1);
          dp[2] = toU8(t2);
          dp[3] = toU8(t3);
        }
      }
    }

    std::vector<uint8_t> triangleResize(const uint8_t* srcRgba, int srcW, int srcH, int dstW, int dstH) {
      // image crate order: vertical first → Rgba32FImage(srcW × dstH)
      //                    horizontal      → RgbaImage(dstW × dstH)
      std::vector<float> tmp((size_t)srcW * (size_t)dstH * 4);
      verticalSampleU8ToF32(srcRgba, srcW, srcH, tmp.data(), dstH);
      std::vector<uint8_t> dst((size_t)dstW * (size_t)dstH * 4);
      horizontalSampleF32ToU8(tmp.data(), srcW, dstH, dst.data(), dstW);
      return dst;
    }

  } // namespace

  std::optional<LoadedImage> loadAndResize(std::string_view path, Scheme scheme, std::string* errorMessage) {
    auto bytes = readFile(path, errorMessage);
    if (bytes.empty())
      return std::nullopt;

    auto decoded = decodeRasterImage(bytes.data(), bytes.size(), errorMessage);
    if (!decoded)
      return std::nullopt;

    const int srcW = decoded->width;
    const int srcH = decoded->height;
    if (srcW <= 0 || srcH <= 0) {
      if (errorMessage)
        *errorMessage = "invalid image dimensions";
      return std::nullopt;
    }

    // Force-resize to 112×112 (aspect ratio ignored, matching matugen which
    // calls `image::imageops::resize(112, 112, Triangle)` — that's a force
    // resize despite the name).
    //
    // Implementation: hand-port of the Rust `image` crate's Triangle resize
    // (separable scale-aware tent filter, no sRGB linearisation). We tried
    // stb_image_resize2 first but its named filters (TRIANGLE/MITCHELL/...)
    // use fixed unit support and severely alias at large downsample ratios;
    // its BOX filter scales but is uniform-weight, leaving a residual ~10°
    // hue offset on certain images. The custom port matches the image crate
    // (matugen's underlying lib) within ≤ 2 LSB per channel.
    (void)scheme;
    std::vector<uint8_t> resizedRgba = triangleResize(decoded->pixels.data(), srcW, srcH, kTarget, kTarget);

    LoadedImage out;
    out.rgb.resize(kTarget * kTarget * 3);
    for (int i = 0; i < kTarget * kTarget; ++i) {
      out.rgb[i * 3 + 0] = resizedRgba[i * 4 + 0];
      out.rgb[i * 3 + 1] = resizedRgba[i * 4 + 1];
      out.rgb[i * 3 + 2] = resizedRgba[i * 4 + 2];
    }
    return out;
  }

} // namespace noctalia::theme
