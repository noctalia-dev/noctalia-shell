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

#include <fstream>

namespace {

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
    if (!file) {
      return {};
    }

    return data;
  }

} // namespace

std::optional<LoadedImageFile> loadImageFile(const std::string& path, int targetSize, std::string* errorMessage) {
  if (path.empty()) {
    if (errorMessage != nullptr) {
      *errorMessage = "empty image path";
    }
    return std::nullopt;
  }

  auto fileData = readFile(path);
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

    const int width = targetSize > 0 ? targetSize : static_cast<int>(image->width);
    const int height = targetSize > 0 ? targetSize : static_cast<int>(image->height);
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
