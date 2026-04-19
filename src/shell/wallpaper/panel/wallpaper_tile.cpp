#include "shell/wallpaper/panel/wallpaper_tile.h"

#include "cursor-shape-v1-client-protocol.h"
#include "render/core/renderer.h"
#include "shell/wallpaper/panel/thumbnail_service.h"
#include "ui/controls/flex.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

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
  setOnMotion([this](const InputArea::PointerData&) {
    if (m_hasEntry && m_onMotion) {
      m_onMotion();
    }
  });
  setOnEnter([this](const InputArea::PointerData&) {
    if (m_hasEntry && m_onEnter) {
      m_onEnter();
    }
  });
  setOnLeave([this]() {
    if (m_hasEntry && m_onLeave) {
      m_onLeave();
    }
  });

  const float padding = Style::spaceXs * m_contentScale;
  const float innerGap = Style::spaceXs * m_contentScale;
  const float labelH = Style::fontSizeCaption * m_contentScale * 1.4f;
  const float frameWidth = std::max(0.0f, cellWidth - padding * 2.0f);
  const float frameHeight = std::max(0.0f, cellHeight - padding * 2.0f - innerGap - labelH);
  const float outlineWidth = Style::borderWidth * 2.0f;
  const float frameRadius = Style::radiusLg * m_contentScale;

  auto layout = std::make_unique<Flex>();
  layout->setDirection(FlexDirection::Vertical);
  layout->setAlign(FlexAlign::Center);
  layout->setGap(innerGap);
  layout->setPadding(padding);
  m_layout = static_cast<Flex*>(addChild(std::move(layout)));
  m_layout->setFrameSize(cellWidth, cellHeight);

  auto thumbBox = std::make_unique<Flex>();
  thumbBox->setDirection(FlexDirection::Vertical);
  thumbBox->setAlign(FlexAlign::Center);
  thumbBox->setJustify(FlexJustify::Center);
  thumbBox->setBackground(roleColor(ColorRole::SurfaceVariant));
  thumbBox->setRadius(frameRadius);
  thumbBox->setMinWidth(frameWidth);
  thumbBox->setMinHeight(frameHeight);
  thumbBox->setFrameSize(frameWidth, frameHeight);
  m_thumbBox = static_cast<Flex*>(m_layout->addChild(std::move(thumbBox)));

  auto image = std::make_unique<Image>();
  image->setFit(ImageFit::Cover);
  image->setCornerRadius(frameRadius);
  image->setBorder(roleColor(ColorRole::Outline), outlineWidth);
  image->setFrameSize(frameWidth, frameHeight);
  m_thumb = static_cast<Image*>(m_thumbBox->addChild(std::move(image)));

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyph("folder");
  glyph->setGlyphSize(std::min(frameWidth, frameHeight) * 0.45f);
  glyph->setColor(roleColor(ColorRole::Primary));
  glyph->setVisible(false);
  m_folderGlyph = static_cast<Glyph*>(m_thumbBox->addChild(std::move(glyph)));

  auto loadingGlyph = std::make_unique<Glyph>();
  loadingGlyph->setGlyph("hourglass");
  loadingGlyph->setGlyphSize(std::min(frameWidth, frameHeight) * 0.32f);
  loadingGlyph->setColor(roleColor(ColorRole::OnSurface, 0.5f));
  loadingGlyph->setVisible(false);
  m_loadingGlyph = static_cast<Glyph*>(m_thumbBox->addChild(std::move(loadingGlyph)));

  auto label = std::make_unique<Label>();
  label->setFontSize(Style::fontSizeCaption * m_contentScale);
  label->setColor(roleColor(ColorRole::OnSurfaceVariant));
  label->setMaxWidth(frameWidth);
  label->setMaxLines(1);
  m_label = static_cast<Label*>(m_layout->addChild(std::move(label)));
}

void WallpaperTile::doLayout(Renderer& renderer) { InputArea::doLayout(renderer); }

void WallpaperTile::setEntry(const WallpaperEntry& entry, Renderer& renderer) {
  const std::string newPath = entry.isDir ? std::string{} : entry.absPath.string();
  const bool sameEntry =
      m_hasEntry && m_entry.absPath == entry.absPath && m_entry.name == entry.name && m_entry.isDir == entry.isDir;
  if (sameEntry) {
    setVisible(true);
    refreshThumbnail(renderer);
    return;
  }

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
    m_loadingThumbnail = false;
    if (m_folderGlyph != nullptr) {
      m_folderGlyph->setVisible(true);
    }
    if (m_loadingGlyph != nullptr) {
      m_loadingGlyph->setVisible(false);
    }
    m_thumbPath.clear();
    applyVisualState();
    return;
  }

  if (m_folderGlyph != nullptr) {
    m_folderGlyph->setVisible(false);
  }
  if (m_loadingGlyph != nullptr) {
    m_loadingGlyph->setVisible(false);
  }
  m_thumb->setVisible(true);
  m_thumbPath = newPath;

  if (m_thumbnails == nullptr) {
    m_thumb->clear(renderer);
    applyVisualState();
    return;
  }

  refreshThumbnail(renderer);
  applyVisualState();
}

void WallpaperTile::clearEntry(Renderer& renderer) {
  if (!m_hasEntry && !visible()) {
    return;
  }
  if (!m_thumbPath.empty() && m_thumbnails != nullptr) {
    m_thumbnails->release(m_thumbPath);
  }
  m_thumbPath.clear();
  if (m_thumb != nullptr) {
    m_thumb->clear(renderer);
  }
  if (m_folderGlyph != nullptr) {
    m_folderGlyph->setVisible(false);
  }
  if (m_loadingGlyph != nullptr) {
    m_loadingGlyph->setVisible(false);
  }
  m_hasEntry = false;
  m_selected = false;
  m_hoveredVisual = false;
  m_loadingThumbnail = false;
  applyVisualState();
  setVisible(false);
}

void WallpaperTile::refreshThumbnail(Renderer& renderer) {
  if (!m_hasEntry || m_entry.isDir || m_thumb == nullptr) {
    return;
  }
  if (m_thumbnails == nullptr || m_thumbPath.empty()) {
    m_thumb->clear(renderer);
    return;
  }

  const TextureHandle handle = m_thumbnails->request(m_thumbPath);
  if (handle.id != 0) {
    m_loadingThumbnail = false;
    m_thumb->setExternalTexture(renderer, handle);
    m_thumb->setVisible(true);
    if (m_loadingGlyph != nullptr) {
      m_loadingGlyph->setVisible(false);
    }
  } else {
    m_loadingThumbnail = true;
    m_thumb->clear(renderer);
    m_thumb->setVisible(false);
    if (m_loadingGlyph != nullptr) {
      m_loadingGlyph->setVisible(true);
    }
  }
}

void WallpaperTile::setSelected(bool selected) {
  if (m_selected == selected) {
    return;
  }
  m_selected = selected;
  applyVisualState();
}

void WallpaperTile::setOnTileClick(ClickCallback callback) { m_onClick = std::move(callback); }
void WallpaperTile::setOnTileMotion(HoverCallback callback) { m_onMotion = std::move(callback); }
void WallpaperTile::setOnTileEnter(HoverCallback callback) { m_onEnter = std::move(callback); }
void WallpaperTile::setOnTileLeave(HoverCallback callback) { m_onLeave = std::move(callback); }

void WallpaperTile::setHoveredVisual(bool hovered) {
  if (m_hoveredVisual == hovered) {
    return;
  }
  m_hoveredVisual = hovered;
  applyVisualState();
}

void WallpaperTile::applyVisualState() {
  if (m_thumbBox == nullptr || m_thumb == nullptr) {
    return;
  }
  const bool active = m_selected || m_hoveredVisual;
  setOpacity(active ? 1.0f : 0.75f);

  const float outlineWidth = Style::borderWidth * 2.0f;
  ThemeColor borderColor = active ? roleColor(ColorRole::Primary) : roleColor(ColorRole::Outline);
  ThemeColor frameBg = roleColor(ColorRole::SurfaceVariant);

  m_thumbBox->setBackground(frameBg);
  if (m_entry.isDir) {
    // Folder tiles hide the image node, so draw the state outline on the frame.
    m_thumbBox->setBorderColor(borderColor);
    m_thumbBox->setBorderWidth(outlineWidth);
    m_thumb->setBorder(roleColor(ColorRole::Outline), outlineWidth);
  } else {
    m_thumbBox->clearBorder();
    m_thumb->setBorder(borderColor, outlineWidth);
  }
}
