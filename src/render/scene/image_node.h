#pragma once

#include "render/core/color.h"
#include "render/scene/node.h"

#include <cstdint>

class ImageNode : public Node {
public:
  ImageNode() : Node(NodeType::Image) {}

  [[nodiscard]] std::uint32_t textureId() const noexcept { return m_textureId; }
  [[nodiscard]] const Color& tint() const noexcept { return m_tint; }
  [[nodiscard]] float cornerRadius() const noexcept { return m_cornerRadius; }

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

private:
  std::uint32_t m_textureId = 0;
  Color m_tint = {1.0f, 1.0f, 1.0f, 1.0f};
  float m_cornerRadius = 0.0f;
};
