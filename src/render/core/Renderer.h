#pragma once

#include <cstdint>
#include <string_view>

class Node;
class TextureManager;
struct wl_display;
struct wl_surface;

struct TextMetrics {
  float width = 0.0f;
  float top = 0.0f;
  float bottom = 0.0f;
};

class Renderer {
public:
  virtual ~Renderer() = default;

  [[nodiscard]] virtual const char* name() const noexcept = 0;

  virtual void bind(wl_display* display, wl_surface* surface) = 0;
  virtual void makeCurrent() = 0;
  virtual void resize(std::uint32_t bufferWidth, std::uint32_t bufferHeight, std::uint32_t logicalWidth,
                      std::uint32_t logicalHeight) = 0;
  virtual void render() = 0;
  virtual void setScene(Node* root) = 0;
  [[nodiscard]] virtual TextMetrics measureText(std::string_view /*text*/, float /*fontSize*/) { return {}; }
  [[nodiscard]] virtual TextMetrics measureGlyph(char32_t /*codepoint*/, float /*fontSize*/) { return {}; }
  [[nodiscard]] virtual TextureManager& textureManager() = 0;
};
