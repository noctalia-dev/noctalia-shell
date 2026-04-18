#include "render/core/texture_manager.h"

#include "core/log.h"

#include "render/core/image_decoder.h"
#include "render/core/image_file_loader.h"

#include <vector>

namespace {

  constexpr Logger kLog("texture");

} // namespace

TextureHandle TextureManager::decodeEncodedRaster(const std::uint8_t* data, std::size_t size,
                                                  const std::string* debugPath, bool mipmap) {
  if (data == nullptr || size == 0) {
    return {};
  }

  std::string errorMessage;
  if (auto decoded = decodeRasterImage(data, size, &errorMessage)) {
    return uploadRgba(decoded->pixels.data(), decoded->width, decoded->height, mipmap);
  }

  if (debugPath != nullptr) {
    kLog.warn("failed to decode image: {} ({})", *debugPath, errorMessage);
  }
  return {};
}

TextureManager::~TextureManager() { cleanup(); }

TextureHandle TextureManager::loadFromFile(const std::string& path, int targetSize, bool mipmap) {
  std::string errorMessage;
  auto loaded = loadImageFile(path, targetSize, &errorMessage);
  if (!loaded.has_value()) {
    if (!errorMessage.empty()) {
      kLog.warn("failed to load image: {} ({})", path, errorMessage);
    } else {
      kLog.warn("failed to load image: {}", path);
    }
    return {};
  }

  return loadFromRgba(loaded->rgba.data(), loaded->width, loaded->height, mipmap);
}

TextureHandle TextureManager::loadFromEncodedBytes(const std::uint8_t* data, std::size_t size, bool mipmap) {
  return decodeEncodedRaster(data, size, nullptr, mipmap);
}

TextureHandle TextureManager::loadFromRgba(const std::uint8_t* data, int width, int height, bool mipmap) {
  if (data == nullptr || width <= 0 || height <= 0) {
    return {};
  }
  return uploadRgba(data, width, height, mipmap);
}

TextureHandle TextureManager::loadFromRaw(const std::uint8_t* data, std::size_t size, int width, int height, int stride,
                                          PixmapFormat format, bool mipmap) {
  if (data == nullptr || size == 0 || width <= 0 || height <= 0) {
    return {};
  }

  const std::size_t channels = (format == PixmapFormat::RGB || format == PixmapFormat::BGR) ? 3U : 4U;
  const std::size_t widthSize = static_cast<std::size_t>(width);
  const std::size_t heightSize = static_cast<std::size_t>(height);
  const std::size_t minStride = widthSize * channels;
  const std::size_t actualStride = stride > 0 ? static_cast<std::size_t>(stride) : minStride;
  if (actualStride < minStride) {
    kLog.warn("raw pixmap stride too small: width={} channels={} stride={}", width, channels, stride);
    return {};
  }

  const std::size_t requiredSize = (heightSize - 1U) * actualStride + minStride;
  if (size < requiredSize) {
    kLog.warn("raw pixmap buffer too small: width={} height={} stride={} have={} need={}", width, height, stride, size,
              requiredSize);
    return {};
  }

  const std::size_t pixelCount = static_cast<std::size_t>(width) * static_cast<std::size_t>(height);
  std::vector<std::uint8_t> rgba(pixelCount * 4);

  for (int y = 0; y < height; ++y) {
    const std::uint8_t* srcRow = data + (y * actualStride);
    std::uint8_t* dstRow = rgba.data() + (y * width * 4);

    for (int x = 0; x < width; ++x) {
      const std::uint8_t* s = srcRow + (static_cast<std::size_t>(x) * channels);
      std::uint8_t* d = dstRow + (x * 4);

      switch (format) {
      case PixmapFormat::RGBA:
        d[0] = s[0];
        d[1] = s[1];
        d[2] = s[2];
        d[3] = s[3];
        break;
      case PixmapFormat::BGRA:
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
        break;
      case PixmapFormat::ARGB:
        d[0] = s[1];
        d[1] = s[2];
        d[2] = s[3];
        d[3] = s[0];
        break;
      case PixmapFormat::RGB:
        d[0] = s[0];
        d[1] = s[1];
        d[2] = s[2];
        d[3] = 255;
        break;
      case PixmapFormat::BGR:
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = 255;
        break;
      }
    }
  }

  return uploadRgba(rgba.data(), width, height, mipmap);
}

void TextureManager::unload(TextureHandle& handle) {
  if (handle.id != 0) {
    glDeleteTextures(1, &handle.id);
    std::erase(m_textures, handle.id);
    handle = {};
  }
}

void TextureManager::cleanup() {
  if (!m_textures.empty()) {
    glDeleteTextures(static_cast<GLsizei>(m_textures.size()), m_textures.data());
    m_textures.clear();
  }
}

TextureHandle TextureManager::uploadRgba(const std::uint8_t* data, int width, int height, bool mipmap) {
  GLuint tex = 0;
  glGenTextures(1, &tex);
  glBindTexture(GL_TEXTURE_2D, tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  if (mipmap) {
    glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  } else {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  }
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

  m_textures.push_back(tex);
  return TextureHandle{.id = tex, .width = width, .height = height};
}
