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
  if (m_image != nullptr) {
    m_image->setCornerRadius(radius);
  }
  if (m_background != nullptr) {
    m_background->setRadius(radius);
  }
  markDirty();
}

void Image::setBorder(const Color& color, float width) {
  if (m_image != nullptr) {
    m_image->setBorder(color, width);
  }
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
  if (m_ownsTexture && path == m_sourcePath && m_texture.id != 0) {
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

  m_ownsTexture = true;
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

  m_ownsTexture = true;
  m_sourcePath.clear();
  if (m_image != nullptr) {
    m_image->setTextureId(m_texture.id);
  }
  updateLayout();
  return true;
}

void Image::setExternalTexture(Renderer& renderer, TextureHandle handle) {
  if (!m_ownsTexture && m_texture.id == handle.id && m_texture.width == handle.width &&
      m_texture.height == handle.height) {
    return;
  }

  if (m_ownsTexture && m_texture.id != 0) {
    renderer.textureManager().unload(m_texture);
  }

  m_texture = handle;
  m_ownsTexture = false;
  m_sourcePath.clear();
  if (m_image != nullptr) {
    m_image->setTextureId(m_texture.id);
  }
  updateLayout();
}

void Image::clear(Renderer& renderer) {
  if (m_ownsTexture && m_texture.id != 0) {
    renderer.textureManager().unload(m_texture);
  }
  m_texture = {};
  m_ownsTexture = false;
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
  m_image->setPosition(m_padding, m_padding);
  m_image->setSize(paddedWidth, paddedHeight);
  m_image->setTextureSize(m_texture.width, m_texture.height);

  ImageFitMode mode = ImageFitMode::Stretch;
  switch (m_fit) {
  case ImageFit::Cover:
    mode = ImageFitMode::Cover;
    break;
  case ImageFit::Contain:
    mode = ImageFitMode::Contain;
    break;
  case ImageFit::Stretch:
    mode = ImageFitMode::Stretch;
    break;
  }
  m_image->setFitMode(mode);
}
