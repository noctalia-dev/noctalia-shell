#include "ui/dialogs/file_entry_tile.h"

#include "render/core/color.h"
#include "render/core/renderer.h"
#include "render/core/thumbnail_service.h"
#include "ui/card_style.h"
#include "ui/controls/box.h"
#include "ui/controls/glyph.h"
#include "ui/controls/image.h"
#include "ui/controls/label.h"
#include "ui/palette.h"
#include "ui/style.h"

#include <algorithm>
#include <cmath>
#include <memory>

namespace {

  constexpr float kPreviewInset = 12.0f;
  constexpr float kPreviewHeightRatio = 0.68f;

} // namespace

FileEntryTile::FileEntryTile(float scale, ThumbnailService* thumbnails) : m_scale(scale), m_thumbnails(thumbnails) {
  setPropagateEvents(true);
  setOnClick([this](const InputArea::PointerData&) {
    if (m_boundIndex != static_cast<std::size_t>(-1) && m_onClick) {
      m_onClick(m_boundIndex);
    }
  });
  setOnMotion([this](const InputArea::PointerData&) {
    if (m_boundIndex != static_cast<std::size_t>(-1) && m_onMotion) {
      m_onMotion(m_boundIndex);
    }
  });
  setOnEnter([this](const InputArea::PointerData&) {
    if (m_boundIndex != static_cast<std::size_t>(-1) && m_onEnter) {
      m_onEnter(m_boundIndex);
    }
  });
  setOnLeave([this]() {
    if (m_boundIndex != static_cast<std::size_t>(-1) && m_onLeave) {
      m_onLeave(m_boundIndex);
    }
  });

  auto background = std::make_unique<Box>();
  background->setRadius(Style::radiusLg * scale);
  m_background = static_cast<Box*>(addChild(std::move(background)));

  auto preview = std::make_unique<Box>();
  ui::applyCardStyle(*preview, scale);
  preview->setRadius(Style::radiusMd * scale);
  m_preview = static_cast<Box*>(addChild(std::move(preview)));

  auto image = std::make_unique<Image>();
  image->setFit(ImageFit::Contain);
  image->setVisible(false);
  m_image = static_cast<Image*>(addChild(std::move(image)));

  auto glyph = std::make_unique<Glyph>();
  glyph->setGlyphSize(36.0f * scale);
  m_glyph = static_cast<Glyph*>(addChild(std::move(glyph)));

  auto label = std::make_unique<Label>();
  label->setFontSize(Style::fontSizeCaption * scale);
  label->setMaxLines(1);
  label->setTextAlign(TextAlign::Center);
  m_label = static_cast<Label*>(addChild(std::move(label)));

  setVisible(false);
}

FileEntryTile::~FileEntryTile() { releaseThumbnail(); }

void FileEntryTile::setCallbacks(IndexCallback onClick, IndexCallback onMotion, IndexCallback onEnter,
                                 IndexCallback onLeave) {
  m_onClick = std::move(onClick);
  m_onMotion = std::move(onMotion);
  m_onEnter = std::move(onEnter);
  m_onLeave = std::move(onLeave);
}

std::string FileEntryTile::bind(Renderer& renderer, const FileEntry& entry, std::size_t index, float width,
                                float height, bool selected, bool hovered, bool disabled) {
  m_boundIndex = index;
  m_selected = selected;
  m_hovered = hovered;
  m_disabled = disabled;
  setVisible(true);
  setEnabled(true);
  setSize(width, height);
  m_background->setSize(width, height);

  m_thumbnailEligible = !entry.isDir && DirectoryScanner::isImagePath(entry.absPath);
  const std::string nextThumbnailPath = m_thumbnailEligible ? entry.absPath.string() : std::string();
  std::string releasedPath;
  if (m_thumbnailPath != nextThumbnailPath) {
    releasedPath = std::move(m_thumbnailPath);
    m_thumbnailPath = nextThumbnailPath;
  }

  m_glyph->setGlyph(entry.isDir ? "folder" : (m_thumbnailEligible ? "image" : "file"));
  m_label->setText(entry.name);
  m_label->setMaxWidth(std::max(0.0f, width - Style::spaceSm * m_scale * 2.0f));

  refreshThumbnail(renderer);
  applyVisualState();
  layout(renderer);
  return releasedPath;
}

void FileEntryTile::refreshThumbnail(Renderer& renderer) {
  if (m_thumbnailEligible && !m_thumbnailPath.empty() && m_thumbnails != nullptr) {
    const TextureHandle handle = m_thumbnails->request(m_thumbnailPath);
    if (handle.id != 0) {
      m_image->setExternalTexture(renderer, handle);
      m_image->setVisible(true);
      m_glyph->setVisible(false);
      return;
    }
  }

  m_image->clear(renderer);
  m_image->setVisible(false);
  m_glyph->setVisible(true);
}

std::string FileEntryTile::clear(Renderer& renderer) {
  std::string releasedPath = std::move(m_thumbnailPath);
  m_image->clear(renderer);
  m_image->setVisible(false);
  m_glyph->setVisible(false);
  m_boundIndex = static_cast<std::size_t>(-1);
  m_selected = false;
  m_hovered = false;
  m_disabled = false;
  m_thumbnailEligible = false;
  setVisible(false);
  return releasedPath;
}

void FileEntryTile::setVisualState(bool selected, bool hovered, bool disabled) {
  if (m_selected == selected && m_hovered == hovered && m_disabled == disabled) {
    return;
  }
  m_selected = selected;
  m_hovered = hovered;
  m_disabled = disabled;
  applyVisualState();
}

void FileEntryTile::doLayout(Renderer& renderer) {
  const float width = this->width();
  const float height = this->height();
  const float previewInset = kPreviewInset * m_scale;
  const float previewWidth = std::max(0.0f, width - previewInset * 2.0f);
  const float previewHeight = std::max(0.0f, height * kPreviewHeightRatio - previewInset);
  const float previewX = previewInset;
  const float previewY = previewInset;
  const float imageInset = Style::spaceSm * m_scale;

  m_background->setPosition(0.0f, 0.0f);
  m_background->setSize(width, height);
  m_preview->setPosition(previewX, previewY);
  m_preview->setSize(previewWidth, previewHeight);

  m_image->setPosition(previewX + imageInset, previewY + imageInset);
  m_image->setSize(std::max(0.0f, previewWidth - imageInset * 2.0f), std::max(0.0f, previewHeight - imageInset * 2.0f));

  if (m_glyph->visible()) {
    m_glyph->measure(renderer);
    m_glyph->setPosition(std::round(previewX + (previewWidth - m_glyph->width()) * 0.5f),
                         std::round(previewY + (previewHeight - m_glyph->height()) * 0.5f));
  }

  m_label->measure(renderer);
  const float labelY = previewY + previewHeight + Style::spaceSm * m_scale;
  m_label->setPosition(std::round((width - m_label->width()) * 0.5f), labelY);

  InputArea::doLayout(renderer);
}

void FileEntryTile::applyVisualState() {
  const Color bg = m_selected  ? resolveThemeColor(roleColor(ColorRole::Primary))
                   : m_hovered ? resolveThemeColor(roleColor(ColorRole::SurfaceVariant, 0.65f))
                               : clearColor();
  const Color fg = m_selected ? resolveThemeColor(roleColor(ColorRole::OnPrimary))
                              : resolveThemeColor(roleColor(ColorRole::OnSurface));
  const float alpha = m_disabled ? 0.55f : 1.0f;

  m_background->setFill(bg);
  m_glyph->setColor(withAlpha(fg, alpha));
  m_label->setColor(withAlpha(fg, alpha));
  markLayoutDirty();
}

void FileEntryTile::releaseThumbnail() {
  if (!m_thumbnailPath.empty() && m_thumbnails != nullptr) {
    m_thumbnails->release(m_thumbnailPath);
  }
  m_thumbnailPath.clear();
}
