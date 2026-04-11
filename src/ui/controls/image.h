#pragma once

#include "render/core/color.h"
#include "render/core/texture_manager.h"
#include "render/scene/node.h"

#include <string>

class Box;
class ImageNode;
class Renderer;

enum class ImageFit : std::uint8_t {
  Contain,
  Cover,
  Stretch,
};

class Image : public Node {
public:
  Image();
  ~Image() override = default;

  void setCornerRadius(float radius);
  void setBackground(const Color& color);
  void setTint(const Color& tint);
  void setFit(ImageFit fit);
  void setPadding(float padding);

  bool setSourceFile(Renderer& renderer, const std::string& path, int targetSize = 0);
  bool setSourceBytes(Renderer& renderer, const std::uint8_t* data, std::size_t size);

  // Binds a texture that is owned externally (e.g. by a shared thumbnail
  // cache). The Image will NOT unload the texture on clear or destruction.
  void setExternalTexture(Renderer& renderer, TextureHandle handle);

  void clear(Renderer& renderer);

  [[nodiscard]] const std::string& sourcePath() const noexcept { return m_sourcePath; }
  [[nodiscard]] bool hasImage() const noexcept { return m_texture.id != 0; }
  [[nodiscard]] int sourceWidth() const noexcept { return m_texture.width; }
  [[nodiscard]] int sourceHeight() const noexcept { return m_texture.height; }
  [[nodiscard]] float aspectRatio() const noexcept {
    return m_texture.width > 0 && m_texture.height > 0
               ? static_cast<float>(m_texture.width) / static_cast<float>(m_texture.height)
               : 1.0f;
  }

  void setSize(float width, float height) override;

private:
  void ensureBackground();
  void updateLayout();

  Box* m_background = nullptr;
  ImageNode* m_image = nullptr;
  TextureHandle m_texture{};
  bool m_ownsTexture = false;
  std::string m_sourcePath;
  float m_cornerRadius = 0.0f;
  float m_padding = 0.0f;
  ImageFit m_fit = ImageFit::Contain;
};
