#pragma once

#include <cstdint>
#include <string_view>

class TextureManager;

enum class TextAlign : std::uint8_t { Start, Center, End };

struct TextMetrics {
  float width = 0.0f;
  float left = 0.0f;
  float right = 0.0f;
  float top = 0.0f;
  float bottom = 0.0f;
  float inkTop = 0.0f;
  float inkBottom = 0.0f;
};

class Renderer {
public:
  virtual ~Renderer() = default;

  [[nodiscard]] virtual TextMetrics measureText(std::string_view text, float fontSize, bool bold = false,
                                                float maxWidth = 0.0f, int maxLines = 0,
                                                TextAlign align = TextAlign::Start) = 0;
  [[nodiscard]] virtual TextMetrics measureGlyph(char32_t codepoint, float fontSize) = 0;
  [[nodiscard]] virtual TextureManager& textureManager() = 0;
};
