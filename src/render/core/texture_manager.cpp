#include "render/core/texture_manager.h"

#include "core/log.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wsign-conversion"
#pragma GCC diagnostic ignored "-Wfloat-conversion"
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wshadow"
#include <nanosvg.h>
#include <nanosvgrast.h>
#pragma GCC diagnostic pop

#include "render/core/image_decoder.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <vector>

namespace {

constexpr Logger kLog("texture");

bool endsWith(const std::string& str, const std::string& suffix) {
  if (suffix.size() > str.size()) {
    return false;
  }
  return std::equal(suffix.rbegin(), suffix.rend(), str.rbegin());
}

std::vector<std::uint8_t> readFile(const std::string& path) {
  std::ifstream file(path, std::ios::binary | std::ios::ate);
  if (!file) {
    return {};
  }
  const auto size = file.tellg();
  if (size <= 0) {
    return {};
  }
  std::vector<std::uint8_t> data(static_cast<std::size_t>(size));
  file.seekg(0);
  file.read(reinterpret_cast<char*>(data.data()), size);
  return data;
}

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
  if (endsWith(path, ".svg") || endsWith(path, ".SVG")) {
    // SVG rasterization via nanosvg
    auto fileData = readFile(path);
    if (fileData.empty()) {
      kLog.warn("failed to read SVG: {}", path);
      return {};
    }

    // nsvgParse needs null-terminated mutable string
    fileData.push_back(0);
    auto* image = nsvgParse(reinterpret_cast<char*>(fileData.data()), "px", 96.0f);
    if (image == nullptr) {
      kLog.warn("failed to parse SVG: {}", path);
      return {};
    }

    int w = targetSize > 0 ? targetSize : static_cast<int>(image->width);
    int h = targetSize > 0 ? targetSize : static_cast<int>(image->height);
    if (w <= 0 || h <= 0) {
      nsvgDelete(image);
      return {};
    }

    float scaleX = static_cast<float>(w) / image->width;
    float scaleY = static_cast<float>(h) / image->height;
    float scale = std::min(scaleX, scaleY);

    auto* rast = nsvgCreateRasterizer();
    if (rast == nullptr) {
      nsvgDelete(image);
      return {};
    }

    std::vector<std::uint8_t> pixels(static_cast<std::size_t>(w * h * 4));
    nsvgRasterize(rast, image, 0, 0, scale, pixels.data(), w, h, w * 4);
    nsvgDeleteRasterizer(rast);
    nsvgDelete(image);

    return uploadRgba(pixels.data(), w, h, mipmap);
  }

  // Raster images via Wuffs' stb-compatible decoder.
  auto fileData = readFile(path);
  if (fileData.empty()) {
    kLog.warn("failed to read image: {}", path);
    return {};
  }

  return decodeEncodedRaster(fileData.data(), fileData.size(), &path, mipmap);
}

TextureHandle TextureManager::loadFromEncodedBytes(const std::uint8_t* data, std::size_t size,
                                                   bool mipmap) {
  return decodeEncodedRaster(data, size, nullptr, mipmap);
}

TextureHandle TextureManager::loadFromArgbPixmap(const std::uint8_t* data, int width, int height,
                                                 bool mipmap) {
  if (data == nullptr || width <= 0 || height <= 0) {
    return {};
  }

  const auto pixelCount = static_cast<std::size_t>(width * height);
  std::vector<std::uint8_t> rgba(pixelCount * 4);

  for (std::size_t i = 0; i < pixelCount; ++i) {
    const std::size_t srcIdx = i * 4;
    const std::size_t dstIdx = i * 4;
    // ARGB → RGBA
    rgba[dstIdx + 0] = data[srcIdx + 1]; // R
    rgba[dstIdx + 1] = data[srcIdx + 2]; // G
    rgba[dstIdx + 2] = data[srcIdx + 3]; // B
    rgba[dstIdx + 3] = data[srcIdx + 0]; // A
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

TextureHandle TextureManager::uploadRgba(const std::uint8_t* data, int width, int height,
                                         bool mipmap) {
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
