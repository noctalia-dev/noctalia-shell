#pragma once

#include <cstdint>
#include <stdexcept>
#include <string_view>

struct Color {
  float r = 0.0f;
  float g = 0.0f;
  float b = 0.0f;
  float a = 1.0f;
};

constexpr Color rgba(float r, float g, float b, float a = 1.0f) { return Color{r, g, b, a}; }

constexpr float colorByte(std::uint32_t value) { return static_cast<float>(value) / 255.0f; }

constexpr Color rgbHex(std::uint32_t value) {
  return Color{
      .r = colorByte((value >> 16U) & 0xFFU),
      .g = colorByte((value >> 8U) & 0xFFU),
      .b = colorByte(value & 0xFFU),
      .a = 1.0f,
  };
}

constexpr Color rgbaHex(std::uint32_t value) {
  return Color{
      .r = colorByte((value >> 24U) & 0xFFU),
      .g = colorByte((value >> 16U) & 0xFFU),
      .b = colorByte((value >> 8U) & 0xFFU),
      .a = colorByte(value & 0xFFU),
  };
}

constexpr std::uint32_t hexDigit(char c) {
  if (c >= '0' && c <= '9') {
    return static_cast<std::uint32_t>(c - '0');
  }
  if (c >= 'a' && c <= 'f') {
    return static_cast<std::uint32_t>(10 + (c - 'a'));
  }
  if (c >= 'A' && c <= 'F') {
    return static_cast<std::uint32_t>(10 + (c - 'A'));
  }
  throw std::invalid_argument("invalid hex digit");
}

constexpr std::uint32_t hexByte(char high, char low) { return (hexDigit(high) << 4U) | hexDigit(low); }

constexpr Color hex(std::string_view value) {
  if (value.empty() || value.front() != '#') {
    throw std::invalid_argument("hex color must start with '#'");
  }

  if (value.size() == 4) {
    return Color{
        .r = colorByte(hexDigit(value[1]) * 17U),
        .g = colorByte(hexDigit(value[2]) * 17U),
        .b = colorByte(hexDigit(value[3]) * 17U),
        .a = 1.0f,
    };
  }

  if (value.size() == 5) {
    return Color{
        .r = colorByte(hexDigit(value[1]) * 17U),
        .g = colorByte(hexDigit(value[2]) * 17U),
        .b = colorByte(hexDigit(value[3]) * 17U),
        .a = colorByte(hexDigit(value[4]) * 17U),
    };
  }

  if (value.size() == 7) {
    return Color{
        .r = colorByte(hexByte(value[1], value[2])),
        .g = colorByte(hexByte(value[3], value[4])),
        .b = colorByte(hexByte(value[5], value[6])),
        .a = 1.0f,
    };
  }

  if (value.size() == 9) {
    return Color{
        .r = colorByte(hexByte(value[1], value[2])),
        .g = colorByte(hexByte(value[3], value[4])),
        .b = colorByte(hexByte(value[5], value[6])),
        .a = colorByte(hexByte(value[7], value[8])),
    };
  }

  throw std::invalid_argument("unsupported hex color format");
}

constexpr Color lerpColor(const Color& a, const Color& b, float t) {
  return Color{
      .r = a.r + (b.r - a.r) * t,
      .g = a.g + (b.g - a.g) * t,
      .b = a.b + (b.b - a.b) * t,
      .a = a.a + (b.a - a.a) * t,
  };
}
