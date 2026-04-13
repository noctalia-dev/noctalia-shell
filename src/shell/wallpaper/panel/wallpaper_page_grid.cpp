#include "shell/wallpaper/panel/wallpaper_page_grid.h"

#include "render/core/renderer.h"
#include "ui/style.h"

#include <cmath>
#include <functional>
#include <memory>

WallpaperPageGrid::WallpaperPageGrid(float contentScale) : m_contentScale(contentScale) {
  m_colGap = Style::spaceMd * m_contentScale;
  m_rowGap = Style::spaceMd * m_contentScale;
}

void WallpaperPageGrid::setPage(const WallpaperEntry* entries, std::size_t count) {
  m_entries = entries;
  m_count = std::min(count, kPageSize);
  markLayoutDirty();
}

void WallpaperPageGrid::setOnTileClick(WallpaperTile::ClickCallback callback) {
  m_onTileClick = std::move(callback);
  for (WallpaperTile* tile : m_pool) {
    if (tile != nullptr) {
      tile->setOnTileClick(m_onTileClick);
    }
  }
}

void WallpaperPageGrid::setOnTileMotion(TileIndexCallback callback) { m_onTileMotion = std::move(callback); }
void WallpaperPageGrid::setOnTileEnter(TileIndexCallback callback) { m_onTileEnter = std::move(callback); }
void WallpaperPageGrid::setOnTileLeave(TileIndexCallback callback) { m_onTileLeave = std::move(callback); }

void WallpaperPageGrid::setRenderer(Renderer* renderer) { m_renderer = renderer; }

void WallpaperPageGrid::setThumbnailService(ThumbnailService* service) {
  m_thumbnails = service;
  for (WallpaperTile* tile : m_pool) {
    if (tile != nullptr) {
      tile->setThumbnailService(service);
    }
  }
}

void WallpaperPageGrid::setHighlightedIndex(std::size_t selectedIndex, std::size_t hoverIndex, bool hoverEnabled) {
  m_selectedIndex = selectedIndex;
  m_hoverIndex = hoverIndex;
  m_hoverEnabled = hoverEnabled;
  markPaintDirty();
}

void WallpaperPageGrid::releaseAllTiles(Renderer& renderer) {
  for (WallpaperTile* tile : m_pool) {
    if (tile != nullptr) {
      tile->clearEntry(renderer);
    }
  }
}

void WallpaperPageGrid::buildPool(float cellW, float cellH) {
  for (std::size_t i = 0; i < kPageSize; ++i) {
    auto tile = std::make_unique<WallpaperTile>(cellW, cellH, m_contentScale);
    tile->setVisible(false);
    tile->setThumbnailService(m_thumbnails);
    if (m_onTileClick) {
      tile->setOnTileClick(m_onTileClick);
    }
    tile->setOnTileMotion([this, i]() {
      if (m_onTileMotion) {
        m_onTileMotion(i);
      }
    });
    tile->setOnTileEnter([this, i]() {
      if (m_onTileEnter) {
        m_onTileEnter(i);
      }
    });
    tile->setOnTileLeave([this, i]() {
      if (m_onTileLeave) {
        m_onTileLeave(i);
      }
    });
    auto* ptr = static_cast<WallpaperTile*>(addChild(std::move(tile)));
    m_pool.push_back(ptr);
  }
}

void WallpaperPageGrid::clearPool() {
  for (WallpaperTile* tile : m_pool) {
    if (tile != nullptr) {
      removeChild(tile);
    }
  }
  m_pool.clear();
}

void WallpaperPageGrid::doLayout(Renderer& renderer) {
  const float W = width();
  const float H = height();
  if (W <= 0.0f || H <= 0.0f) {
    return;
  }

  const float cellW = (W - static_cast<float>(kColumns - 1) * m_colGap) / static_cast<float>(kColumns);
  const float cellH = (H - static_cast<float>(kRows - 1) * m_rowGap) / static_cast<float>(kRows);

  const bool poolEmpty = m_pool.empty();
  const bool sizeChanged = !poolEmpty &&
                           (std::abs(cellW - m_cellW) > 0.5f || std::abs(cellH - m_cellH) > 0.5f);
  if (poolEmpty || sizeChanged) {
    clearPool();
    buildPool(cellW, cellH);
    m_cellW = cellW;
    m_cellH = cellH;
  }

  if (m_renderer == nullptr) {
    for (WallpaperTile* tile : m_pool) {
      tile->setVisible(false);
    }
    return;
  }

  for (std::size_t i = 0; i < kPageSize; ++i) {
    WallpaperTile* tile = m_pool[i];
    if (i < m_count) {
      const std::size_t row = i / kColumns;
      const std::size_t col = i % kColumns;
      tile->setPosition(static_cast<float>(col) * (cellW + m_colGap),
                        static_cast<float>(row) * (cellH + m_rowGap));
      tile->setEntry(m_entries[i], *m_renderer);
      tile->setSelected(i == m_selectedIndex);
      tile->setHoveredVisual(m_hoverEnabled && i == m_hoverIndex && i != m_selectedIndex);
    } else {
      tile->clearEntry(renderer);
    }
  }

  for (auto& child : children()) {
    if (child->visible()) {
      child->layout(renderer);
    }
  }
}
