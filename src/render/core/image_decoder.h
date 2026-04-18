#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

struct DecodedRasterImage {
  std::vector<std::uint8_t> pixels;
  int width = 0;
  int height = 0;
};

[[nodiscard]] std::optional<DecodedRasterImage> decodeRasterImage(const std::uint8_t* data, std::size_t size,
                                                                  std::string* errorMessage = nullptr);
