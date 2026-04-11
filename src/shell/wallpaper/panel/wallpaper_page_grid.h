#pragma once

#include "render/scene/node.h"
#include "shell/wallpaper/panel/wallpaper_scanner.h"
#include "shell/wallpaper/panel/wallpaper_tile.h"

#include <cstddef>
#include <vector>

class Renderer;
class ThumbnailService;

// Fixed-size paged grid of WallpaperTiles. Holds a pool of exactly
// kColumns*kRows tiles and binds them to the entries for the current page,
// computing cell size adaptively from its own width/height. No scroll, no
// virtualization, no cache: page changes release old thumbnails through the
// ThumbnailService and request new ones.
class WallpaperPageGrid : public Node {
public:
  using TileIndexCallback = std::function<void(std::size_t index)>;

  static constexpr std::size_t kColumns = 5;
  static constexpr std::size_t kRows = 4;
  static constexpr std::size_t kPageSize = kColumns * kRows;

  explicit WallpaperPageGrid(float contentScale);

  // Bind the grid to the current page's entries. `count` must be <= kPageSize.
  // Passing count==0 clears the grid without releasing textures (the caller
  // is responsible for releasing through the ThumbnailService directly).
  void setPage(const WallpaperEntry* entries, std::size_t count);

  void setOnTileClick(WallpaperTile::ClickCallback callback);
  void setOnTileMotion(TileIndexCallback callback);
  void setOnTileEnter(TileIndexCallback callback);
  void setOnTileLeave(TileIndexCallback callback);
  void setRenderer(Renderer* renderer);
  void setThumbnailService(ThumbnailService* service);
  void setHighlightedIndex(std::size_t selectedIndex, std::size_t hoverIndex, bool hoverEnabled);

  // Release and clear every tile's current thumbnail. Called by the panel on
  // close so no GL textures outlive the panel.
  void releaseAllTiles(Renderer& renderer);

  void layout(Renderer& renderer) override;

private:
  void buildPool(float cellW, float cellH);
  void clearPool();

  float m_contentScale;
  float m_colGap;
  float m_rowGap;
  float m_cellW = 0.0f;
  float m_cellH = 0.0f;

  const WallpaperEntry* m_entries = nullptr;
  std::size_t m_count = 0;

  Renderer* m_renderer = nullptr;
  ThumbnailService* m_thumbnails = nullptr;

  std::vector<WallpaperTile*> m_pool;
  WallpaperTile::ClickCallback m_onTileClick;
  TileIndexCallback m_onTileMotion;
  TileIndexCallback m_onTileEnter;
  TileIndexCallback m_onTileLeave;
  std::size_t m_selectedIndex = kPageSize;
  std::size_t m_hoverIndex = kPageSize;
  bool m_hoverEnabled = false;
};
