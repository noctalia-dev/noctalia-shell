#pragma once

#include <cstdint>

struct NetworkState;

namespace network_glyphs {

  [[nodiscard]] const char* glyphForState(const NetworkState& state) noexcept;
  [[nodiscard]] const char* wifiGlyphForState(const NetworkState& state) noexcept;
  [[nodiscard]] const char* wifiGlyphForSignal(std::uint8_t signal) noexcept;

} // namespace network_glyphs
