#pragma once

#include <cstdint>
#include <string>
#include <vector>

// Encode an RGBA8 (non-premultiplied) pixel buffer to PNG bytes. Counterpart to image_decoder.
// Callers that need a file write the returned buffer themselves (avoids re-encoding).

[[nodiscard]] std::vector<std::uint8_t>
encodePng(const std::uint8_t* rgba, int width, int height, std::string* errorOut = nullptr);
