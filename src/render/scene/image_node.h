#pragma once

#include "render/core/color.h"
#include "render/core/texture_handle.h"
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

  [[nodiscard]] TextureId textureId() const noexcept { return m_textureId; }
  [[nodiscard]] const Color& tint() const noexcept { return m_tint; }
  [[nodiscard]] float radius() const noexcept { return m_radius; }
  [[nodiscard]] const Color& borderColor() const noexcept { return m_borderColor; }
  [[nodiscard]] float borderWidth() const noexcept { return m_borderWidth; }
  [[nodiscard]] ImageFitMode fitMode() const noexcept { return m_fitMode; }
  [[nodiscard]] int textureWidth() const noexcept { return m_textureWidth; }
  [[nodiscard]] int textureHeight() const noexcept { return m_textureHeight; }

  void setTextureId(TextureId id) {
    if (m_textureId == id) {
      return;
    }
    m_textureId = id;
    markPaintDirty();
  }

  void setTint(const Color& tint) {
    if (m_tint == tint) {
      return;
    }
    m_tint = tint;
    markPaintDirty();
  }

  void setRadius(float radius) {
    if (m_radius == radius) {
      return;
    }
    m_radius = radius;
    markPaintDirty();
  }

  void setBorder(const Color& color, float width) {
    if (m_borderColor == color && m_borderWidth == width) {
      return;
    }
    m_borderColor = color;
    m_borderWidth = width;
    markPaintDirty();
  }

  void setFitMode(ImageFitMode mode) {
    if (m_fitMode == mode) {
      return;
    }
    m_fitMode = mode;
    markPaintDirty();
  }

  void setTextureSize(int width, int height) {
    if (m_textureWidth == width && m_textureHeight == height) {
      return;
    }
    m_textureWidth = width;
    m_textureHeight = height;
    markLayoutDirty();
  }

private:
  TextureId m_textureId;
  Color m_tint = {1.0f, 1.0f, 1.0f, 1.0f};
  float m_radius = 0.0f;
  Color m_borderColor = {0.0f, 0.0f, 0.0f, 0.0f};
  float m_borderWidth = 0.0f;
  ImageFitMode m_fitMode = ImageFitMode::Stretch;
  int m_textureWidth = 0;
  int m_textureHeight = 0;
};
