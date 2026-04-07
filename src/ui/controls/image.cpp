#include "ui/controls/image.h"

#include "render/core/renderer.h"
#include "render/scene/image_node.h"
#include "ui/controls/box.h"

#include <algorithm>
#include <cmath>
#include <memory>

Image::Image() {
  setClipChildren(true);

  auto image = std::make_unique<ImageNode>();
  m_image = static_cast<ImageNode*>(addChild(std::move(image)));
}

void Image::ensureBackground() {
  if (m_background != nullptr) {
    return;
  }
  auto background = std::make_unique<Box>();
  m_background = static_cast<Box*>(addChild(std::move(background)));
  m_background->setZIndex(-1);
  m_background->setFlatStyle();
  m_background->setSize(width(), height());
  if (m_cornerRadius != 0.0f) {
    m_background->setRadius(m_cornerRadius);
  }
}

void Image::setCornerRadius(float radius) {
  if (m_cornerRadius == radius) {
    return;
  }
  m_cornerRadius = radius;
  if (m_background != nullptr) {
    m_background->setRadius(radius);
  }
  markDirty();
}

void Image::setBackground(const Color& color) {
  ensureBackground();
  m_background->setFill(color);
  m_background->setBorder(color, 0.0f);
}

void Image::setTint(const Color& tint) {
  if (m_image != nullptr) {
    m_image->setTint(tint);
  }
}

void Image::setFit(ImageFit fit) {
  if (m_fit == fit) {
    return;
  }
  m_fit = fit;
  updateLayout();
}

void Image::setPadding(float padding) {
  if (m_padding == padding) {
    return;
  }
  m_padding = padding;
  updateLayout();
}

bool Image::setSourceFile(Renderer& renderer, const std::string& path, int targetSize) {
  if (path == m_sourcePath && m_texture.id != 0) {
    return true;
  }

  clear(renderer);

  if (path.empty()) {
    return false;
  }

  m_texture = renderer.textureManager().loadFromFile(path, targetSize);
  if (m_texture.id == 0) {
    m_sourcePath.clear();
    if (m_image != nullptr) {
      m_image->setTextureId(0);
    }
    return false;
  }

  m_sourcePath = path;
  if (m_image != nullptr) {
    m_image->setTextureId(m_texture.id);
  }
  updateLayout();
  return true;
}

bool Image::setSourceBytes(Renderer& renderer, const std::uint8_t* data, std::size_t size) {
  clear(renderer);

  if (data == nullptr || size == 0) {
    return false;
  }

  m_texture = renderer.textureManager().loadFromEncodedBytes(data, size);
  if (m_texture.id == 0) {
    m_sourcePath.clear();
    if (m_image != nullptr) {
      m_image->setTextureId(0);
    }
    return false;
  }

  m_sourcePath.clear();
  if (m_image != nullptr) {
    m_image->setTextureId(m_texture.id);
  }
  updateLayout();
  return true;
}

void Image::clear(Renderer& renderer) {
  if (m_texture.id != 0) {
    renderer.textureManager().unload(m_texture);
  }
  m_sourcePath.clear();
  if (m_image != nullptr) {
    m_image->setTextureId(0);
    m_image->setSize(0.0f, 0.0f);
  }
}

void Image::setSize(float width, float height) {
  Node::setSize(width, height);
  updateLayout();
}

void Image::updateLayout() {
  if (m_background != nullptr) {
    m_background->setSize(width(), height());
  }

  if (m_image == nullptr) {
    return;
  }

  const float paddedWidth = std::max(0.0f, width() - m_padding * 2.0f);
  const float paddedHeight = std::max(0.0f, height() - m_padding * 2.0f);
  if (m_texture.id == 0 || paddedWidth <= 0.0f || paddedHeight <= 0.0f || m_texture.width <= 0 || m_texture.height <= 0) {
    m_image->setPosition(m_padding, m_padding);
    m_image->setSize(paddedWidth, paddedHeight);
    return;
  }

  float imageWidth = paddedWidth;
  float imageHeight = paddedHeight;

  if (m_fit != ImageFit::Stretch) {
    const float textureWidth = static_cast<float>(m_texture.width);
    const float textureHeight = static_cast<float>(m_texture.height);
    const float scaleX = paddedWidth / textureWidth;
    const float scaleY = paddedHeight / textureHeight;
    const float scale = (m_fit == ImageFit::Cover) ? std::max(scaleX, scaleY) : std::min(scaleX, scaleY);
    imageWidth = std::max(0.0f, textureWidth * scale);
    imageHeight = std::max(0.0f, textureHeight * scale);
  }

  const float imageX = m_padding + std::round((paddedWidth - imageWidth) * 0.5f);
  const float imageY = m_padding + std::round((paddedHeight - imageHeight) * 0.5f);
  m_image->setPosition(imageX, imageY);
  m_image->setSize(imageWidth, imageHeight);
}
