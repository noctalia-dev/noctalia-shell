#pragma once

#include <cstdint>

namespace KeyMod {
  inline constexpr std::uint32_t Shift = 1u << 0;
  inline constexpr std::uint32_t Ctrl = 1u << 1;
  inline constexpr std::uint32_t Alt = 1u << 2;
  inline constexpr std::uint32_t Super = 1u << 3;
} // namespace KeyMod
