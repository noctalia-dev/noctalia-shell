#pragma once

#include "render/core/texture_handle.h"

#include <cstdint>
#include <string>
#include <vector>

enum class PixmapFormat {
  RGBA, // Red, Green, Blue, Alpha
  BGRA, // Blue, Green, Red, Alpha
  ARGB, // Alpha, Red, Green, Blue
  RGB,  // Red, Green, Blue (No Alpha)
  BGR   // Blue, Green, Red (No Alpha)
};

enum class TextureDataFormat {
  Alpha,
  LuminanceAlpha,
  Rgba,
};

enum class TextureFilter {
  Nearest,
  Linear,
};

class TextureManager {
public:
  TextureManager() = default;
  ~TextureManager();

  TextureManager(const TextureManager&) = delete;
  TextureManager& operator=(const TextureManager&) = delete;

  [[nodiscard]] TextureHandle loadFromFile(const std::string& path, int targetSize = 0, bool mipmap = false);
  [[nodiscard]] TextureHandle loadFromEncodedBytes(const std::uint8_t* data, std::size_t size, bool mipmap = false);
  [[nodiscard]] TextureHandle loadFromRgba(const std::uint8_t* data, int width, int height, bool mipmap = false);
  [[nodiscard]] TextureHandle loadFromRaw(const std::uint8_t* data, std::size_t size, int width, int height, int stride,
                                          PixmapFormat format, bool mipmap = false);
  [[nodiscard]] TextureHandle loadFromPixels(const std::uint8_t* data, int width, int height, TextureDataFormat format,
                                             TextureFilter filter = TextureFilter::Linear, bool mipmap = false);
  [[nodiscard]] TextureHandle createEmpty(int width, int height, TextureDataFormat format,
                                          TextureFilter filter = TextureFilter::Linear);
  bool replace(TextureHandle& handle, const std::uint8_t* data, int width, int height, TextureDataFormat format,
               TextureFilter filter = TextureFilter::Linear, bool mipmap = false);
  bool updateSubImage(TextureHandle& handle, const std::uint8_t* data, int x, int y, int width, int height,
                      TextureDataFormat format);
  void unload(TextureHandle& handle);
  void cleanup();

  void probeExtensions();

private:
  TextureHandle decodeEncodedRaster(const std::uint8_t* data, std::size_t size, const std::string* debugPath = nullptr,
                                    bool mipmap = false);
  TextureHandle uploadPixels(const std::uint8_t* data, int width, int height, TextureDataFormat format,
                             TextureFilter filter = TextureFilter::Linear, bool mipmap = false);
  TextureHandle uploadRgba(const std::uint8_t* data, int width, int height, bool mipmap = false);
  TextureHandle uploadBgra(const std::uint8_t* data, int width, int height, bool mipmap = false);
  std::vector<TextureId> m_textures;
  bool m_hasBgraExt = false;
};
