#pragma once

#include <cstdint>
#include <string_view>

class TextureManager;

struct TextMetrics {
  float width = 0.0f;
  float top = 0.0f;
  float bottom = 0.0f;
};

class Renderer {
public:
  virtual ~Renderer() = default;

  [[nodiscard]] virtual TextMetrics measureText(std::string_view text, float fontSize, bool bold = false) = 0;
  [[nodiscard]] virtual TextMetrics measureGlyph(char32_t codepoint, float fontSize) = 0;
  [[nodiscard]] virtual TextureManager& textureManager() = 0;
};
