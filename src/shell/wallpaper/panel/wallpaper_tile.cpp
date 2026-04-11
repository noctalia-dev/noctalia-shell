#include "shell/wallpaper/panel/wallpaper_tile.h"

#include "render/core/renderer.h"
#include "shell/wallpaper/panel/thumbnail_service.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include "cursor-shape-v1-client-protocol.h"

#include <algorithm>
#include <memory>
#include <utility>

WallpaperTile::WallpaperTile(float cellWidth, float cellHeight, float contentScale)
    : m_cellWidth(cellWidth), m_cellHeight(cellHeight), m_contentScale(contentScale) {
  setSize(cellWidth, cellHeight);
  setAcceptedButtons(BTN_LEFT);
  setCursorShape(WP_CURSOR_SHAPE_DEVICE_V1_SHAPE_POINTER);
  setOnClick([this](const InputArea::PointerData&) {
    if (m_hasEntry && m_onClick) {
      m_onClick(m_entry);
    }
  });

  const float padding = Style::spaceXs * m_contentScale;
  const float innerGap = Style::spaceXs * m_contentScale;
  const float labelH = Style::fontSizeCaption * m_contentScale * 1.4f;
  const float thumbW = std::max(0.0f, cellWidth - padding * 2.0f);
  const float thumbH = std::max(0.0f, cellHeight - padding * 2.0f - innerGap - labelH);

  auto layout = std::make_unique<Flex>();
  layout->setDirection(FlexDirection::Vertical);
  layout->setAlign(FlexAlign::Center);
  layout->setGap(innerGap);
  layout->setPadding(padding);
  m_layout = static_cast<Flex*>(addChild(std::move(layout)));
  m_layout->setSize(cellWidth, cellHeight);

  auto thumbBox = std::make_unique<Flex>();
  thumbBox->setDirection(FlexDirection::Vertical);
  thumbBox->setAlign(FlexAlign::Center);
  thumbBox->setJustify(FlexJustify::Center);
  thumbBox->setBackground(palette.surfaceVariant);
  thumbBox->setBorderColor(palette.outline);
  thumbBox->setBorderWidth(Style::borderWidth);
  thumbBox->setRadius(Style::radiusLg * m_contentScale);
  thumbBox->setMinWidth(thumbW);
  thumbBox->setMinHeight(thumbH);
  thumbBox->setSize(thumbW, thumbH);
  m_thumbBox = static_cast<Flex*>(m_layout->addChild(std::move(thumbBox)));

  auto image = std::make_unique<Image>();
  image->setFit(ImageFit::Cover);
  image->setCornerRadius(Style::radiusLg * m_contentScale);
  image->setSize(thumbW, thumbH);
  m_thumb = static_cast<Image*>(m_thumbBox->addChild(std::move(image)));

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("folder");
  glyph->setGlyphSize(std::min(thumbW, thumbH) * 0.45f);
  glyph->setColor(palette.primary);
  glyph->setVisible(false);
  m_folderGlyph = static_cast<Glyph*>(m_thumbBox->addChild(std::move(glyph)));

  auto label = std::make_unique<Label>();
  label->setFontSize(Style::fontSizeCaption * m_contentScale);
  label->setColor(palette.onSurfaceVariant);
  label->setMaxWidth(thumbW);
  label->setMaxLines(1);
  m_label = static_cast<Label*>(m_layout->addChild(std::move(label)));
}

void WallpaperTile::setEntry(const WallpaperEntry& entry, Renderer& renderer) {
  const std::string newPath = entry.isDir ? std::string{} : entry.absPath.string();
  if (!m_thumbPath.empty() && m_thumbPath != newPath && m_thumbnails != nullptr) {
    m_thumbnails->release(m_thumbPath);
  }

  m_entry = entry;
  m_hasEntry = true;
  setVisible(true);

  m_label->setText(entry.name);

  if (entry.isDir) {
    m_thumb->clear(renderer);
    m_thumb->setVisible(false);
    if (m_folderGlyph != nullptr) {
      m_folderGlyph->setVisible(true);
    }
    m_thumbPath.clear();
    return;
  }

  if (m_folderGlyph != nullptr) {
    m_folderGlyph->setVisible(false);
  }
  m_thumb->setVisible(true);
  m_thumbPath = newPath;

  if (m_thumbnails == nullptr) {
    m_thumb->clear(renderer);
    return;
  }

  TextureHandle handle = m_thumbnails->request(newPath);
  if (handle.id != 0) {
    m_thumb->setExternalTexture(renderer, handle);
  } else {
    m_thumb->clear(renderer);
  }
}

void WallpaperTile::clearEntry(Renderer& renderer) {
  if (!m_thumbPath.empty() && m_thumbnails != nullptr) {
    m_thumbnails->release(m_thumbPath);
  }
  m_thumbPath.clear();
  if (m_thumb != nullptr) {
    m_thumb->clear(renderer);
  }
  m_hasEntry = false;
  setVisible(false);
}

void WallpaperTile::setSelected(bool selected) {
  if (m_selected == selected) {
    return;
  }
  m_selected = selected;
  applySelection();
}

void WallpaperTile::setOnTileClick(ClickCallback callback) { m_onClick = std::move(callback); }

void WallpaperTile::applySelection() {
  if (m_thumbBox == nullptr) {
    return;
  }
  if (m_selected) {
    m_thumbBox->setBorderColor(palette.primary);
    m_thumbBox->setBorderWidth(Style::borderWidth * 2.0f);
  } else {
    m_thumbBox->setBorderColor(palette.outline);
    m_thumbBox->setBorderWidth(Style::borderWidth);
  }
}
