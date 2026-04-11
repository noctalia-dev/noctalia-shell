#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <cstdint>

enum class ImageFitMode : std::uint8_t {
  Stretch,
  Cover,
  Contain,
};

class ImageNode : public Node {
public:
  ImageNode() : Node(NodeType::Image) {}

  [[nodiscard]] std::uint32_t textureId() const noexcept { return m_textureId; }
  [[nodiscard]] const Color& tint() const noexcept { return m_tint; }
  [[nodiscard]] float cornerRadius() const noexcept { return m_cornerRadius; }
  [[nodiscard]] const Color& borderColor() const noexcept { return m_borderColor; }
  [[nodiscard]] float borderWidth() const noexcept { return m_borderWidth; }
  [[nodiscard]] ImageFitMode fitMode() const noexcept { return m_fitMode; }
  [[nodiscard]] int textureWidth() const noexcept { return m_textureWidth; }
  [[nodiscard]] int textureHeight() const noexcept { return m_textureHeight; }

  void setTextureId(std::uint32_t id) {
    if (m_textureId == id) {
      return;
    }
    m_textureId = id;
    markDirty();
  }

  void setTint(const Color& tint) {
    m_tint = tint;
    markDirty();
  }

  void setCornerRadius(float radius) {
    if (m_cornerRadius == radius) {
      return;
    }
    m_cornerRadius = radius;
    markDirty();
  }

  void setBorder(const Color& color, float width) {
    m_borderColor = color;
    m_borderWidth = width;
    markDirty();
  }

  void setFitMode(ImageFitMode mode) {
    if (m_fitMode == mode) {
      return;
    }
    m_fitMode = mode;
    markDirty();
  }

  void setTextureSize(int width, int height) {
    if (m_textureWidth == width && m_textureHeight == height) {
      return;
    }
    m_textureWidth = width;
    m_textureHeight = height;
    markDirty();
  }

private:
  std::uint32_t m_textureId = 0;
  Color m_tint = {1.0f, 1.0f, 1.0f, 1.0f};
  float m_cornerRadius = 0.0f;
  Color m_borderColor = {0.0f, 0.0f, 0.0f, 0.0f};
  float m_borderWidth = 0.0f;
  ImageFitMode m_fitMode = ImageFitMode::Stretch;
  int m_textureWidth = 0;
  int m_textureHeight = 0;
};
