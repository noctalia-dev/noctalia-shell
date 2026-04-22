#include "render/scene/graph_node.h"

#include <algorithm>
#include <cstdint>
#include <vector>

GraphNode::~GraphNode() {
  if (m_texture != 0) {
    glDeleteTextures(1, &m_texture);
  }
}

void GraphNode::setData(const float* primary, int primaryCount, const float* secondary, int secondaryCount) {
  const int newWidth = std::max({primaryCount + 1, secondaryCount + 1, 4});

  std::vector<std::uint8_t> pixels(static_cast<std::size_t>(newWidth) * 2, 0);
  for (int i = 0; i < newWidth; ++i) {
    float lum = (i < primaryCount) ? primary[i] : (primaryCount > 0 ? primary[primaryCount - 1] : 0.0f);
    float alp = (i < secondaryCount) ? secondary[i] : (secondaryCount > 0 ? secondary[secondaryCount - 1] : 0.0f);
    pixels[static_cast<std::size_t>(i) * 2] = static_cast<std::uint8_t>(std::clamp(lum, 0.0f, 1.0f) * 255.0f);
    pixels[static_cast<std::size_t>(i) * 2 + 1] = static_cast<std::uint8_t>(std::clamp(alp, 0.0f, 1.0f) * 255.0f);
  }

  if (m_texture == 0) {
    glGenTextures(1, &m_texture);
  }

  glBindTexture(GL_TEXTURE_2D, m_texture);

  if (newWidth > m_texCapacity) {
    m_texCapacity = newWidth;
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE_ALPHA, newWidth, 1, 0, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE,
                 pixels.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  } else {
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, newWidth, 1, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, pixels.data());
  }

  m_texWidth = newWidth;
  markPaintDirty();
}
