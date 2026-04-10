#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>

namespace noctalia::theme {

  // A fully-generated palette, keyed by the token names from tokens.h. Values
  // are packed ARGB (0xffRRGGBB). Serialization to "#rrggbb" lives in
  // json_output.cpp.
  struct GeneratedPalette {
    std::unordered_map<std::string, uint32_t> dark;
    std::unordered_map<std::string, uint32_t> light;
  };

} // namespace noctalia::theme
