#include "render/core/image_file_loader.h"

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
#include "util/file_utils.h"

#include <algorithm>
#include <cmath>
#include <fstream>

namespace {} // namespace

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
    // nsvgParse needs a null-terminated mutable string.
    fileData.push_back(0);
    auto* image = nsvgParse(reinterpret_cast<char*>(fileData.data()), "px", 96.0f);
    if (image == nullptr) {
      if (errorMessage != nullptr) {
        *errorMessage = "failed to parse SVG";
      }
      return std::nullopt;
    }

    int width = static_cast<int>(image->width);
    int height = static_cast<int>(image->height);
    if (targetSize > 0 && image->width > 0.0f && image->height > 0.0f) {
      // Preserve source aspect ratio and constrain the longer side to targetSize.
      const float maxSide = std::max(image->width, image->height);
      const float scale = static_cast<float>(targetSize) / maxSide;
      width = std::max(1, static_cast<int>(std::round(image->width * scale)));
      height = std::max(1, static_cast<int>(std::round(image->height * scale)));
    }
    if (width <= 0 || height <= 0) {
      if (errorMessage != nullptr) {
        *errorMessage = "invalid SVG dimensions";
      }
      nsvgDelete(image);
      return std::nullopt;
    }

    const float scaleX = static_cast<float>(width) / image->width;
    const float scaleY = static_cast<float>(height) / image->height;
    const float scale = std::min(scaleX, scaleY);

    auto* rast = nsvgCreateRasterizer();
    if (rast == nullptr) {
      if (errorMessage != nullptr) {
        *errorMessage = "failed to create SVG rasterizer";
      }
      nsvgDelete(image);
      return std::nullopt;
    }

    LoadedImageFile loaded{
        .rgba = std::vector<std::uint8_t>(static_cast<std::size_t>(width) * static_cast<std::size_t>(height) * 4U),
        .width = width,
        .height = height,
    };
    nsvgRasterize(rast, image, 0, 0, scale, loaded.rgba.data(), width, height, width * 4);
    nsvgDeleteRasterizer(rast);
    nsvgDelete(image);
    return loaded;
  }

  if (auto decoded = decodeRasterImage(fileData.data(), fileData.size(), errorMessage)) {
    return LoadedImageFile{.rgba = std::move(decoded->pixels), .width = decoded->width, .height = decoded->height};
  }

  return std::nullopt;
}
