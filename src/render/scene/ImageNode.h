#pragma once

#include "render/core/Color.h"
#include "render/scene/Node.h"

#include <cstdint>

class ImageNode : public Node {
public:
  ImageNode() : Node(NodeType::Image) {}

  [[nodiscard]] std::uint32_t textureId() const noexcept { return m_textureId; }
  [[nodiscard]] const Color& tint() const noexcept { return m_tint; }

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

private:
  std::uint32_t m_textureId = 0;
  Color m_tint = {1.0f, 1.0f, 1.0f, 1.0f};
};
