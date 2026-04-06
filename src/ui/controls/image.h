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
  void updateLayout();

  Box* m_background = nullptr;
  ImageNode* m_image = nullptr;
  TextureHandle m_texture{};
  std::string m_sourcePath;
  float m_cornerRadius = 0.0f;
  float m_padding = 0.0f;
  ImageFit m_fit = ImageFit::Contain;
};
