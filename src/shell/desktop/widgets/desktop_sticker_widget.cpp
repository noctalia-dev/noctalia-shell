#include "shell/desktop/widgets/desktop_sticker_widget.h"

#include "render/core/renderer.h"
#include "render/scene/node.h"
#include "ui/controls/image.h"

#include <memory>

namespace {

  constexpr float kDefaultStickerSize = 200.0f;

} // namespace

DesktopStickerWidget::DesktopStickerWidget(std::string imagePath) : m_imagePath(std::move(imagePath)) {}

void DesktopStickerWidget::create() {
  auto rootNode = std::make_unique<Node>();

  auto image = std::make_unique<Image>();
  image->setFit(ImageFit::Contain);
  m_image = image.get();

  rootNode->addChild(std::move(image));
  setRoot(std::move(rootNode));
}

void DesktopStickerWidget::doLayout(Renderer& renderer) {
  if (m_image == nullptr || root() == nullptr) {
    return;
  }

  if (!m_loaded && !m_imagePath.empty()) {
    m_image->setSourceFile(renderer, m_imagePath);
    m_loaded = true;
  }

  const float baseSize = kDefaultStickerSize * contentScale();
  float width = baseSize;
  float height = baseSize;

  if (m_image->hasImage()) {
    const float ar = m_image->aspectRatio();
    if (ar >= 1.0f) {
      height = baseSize / ar;
    } else {
      width = baseSize * ar;
    }
  }

  m_image->setSize(width, height);
  root()->setSize(width, height);
}
