#pragma once

#include "render/scene/input_area.h"
#include "shell/wallpaper/panel/wallpaper_scanner.h"

#include <functional>
#include <string>

class Flex;
class Glyph;
class Image;
class Label;
class RectNode;
class Renderer;
class ThumbnailService;

// A single cell in the wallpaper grid: rounded thumbnail (or folder glyph for
// directories) with filename underneath. Inherits InputArea so the whole tile
// is clickable. Pooled and reused by VirtualWallpaperGrid as the viewport
// scrolls.
class WallpaperTile : public InputArea {
public:
  using ClickCallback = std::function<void(const WallpaperEntry&)>;
  using HoverCallback = std::function<void()>;

  WallpaperTile(float cellWidth, float cellHeight, float contentScale);
  void layout(Renderer& renderer) override;

  // Non-owning pointer to the shared async thumbnail service. If null, tiles
  // will leave their image blank.
  void setThumbnailService(ThumbnailService* service) { m_thumbnails = service; }

  // Bind the tile to an entry. For image entries, a thumbnail is requested
  // from the service; if the previous binding was also an image, its
  // thumbnail is released first so the service only holds textures for the
  // current page.
  void setEntry(const WallpaperEntry& entry, Renderer& renderer);

  // Detach from the current entry and release any held thumbnail.
  void clearEntry(Renderer& renderer);

  void setSelected(bool selected);
  void setHoveredVisual(bool hovered);
  void setOnTileClick(ClickCallback callback);
  void setOnTileMotion(HoverCallback callback);
  void setOnTileEnter(HoverCallback callback);
  void setOnTileLeave(HoverCallback callback);

  [[nodiscard]] const WallpaperEntry* entry() const noexcept { return m_hasEntry ? &m_entry : nullptr; }

private:
  void applyVisualState();
  void syncOutlineGeometry();

  float m_cellWidth;
  float m_cellHeight;
  float m_contentScale;

  Flex* m_layout = nullptr;
  Flex* m_thumbBox = nullptr;
  Image* m_thumb = nullptr;
  Glyph* m_folderGlyph = nullptr;
  RectNode* m_outline = nullptr;
  Label* m_label = nullptr;

  WallpaperEntry m_entry;
  bool m_hasEntry = false;
  bool m_selected = false;
  bool m_hoveredVisual = false;
  std::string m_thumbPath;
  ClickCallback m_onClick;
  HoverCallback m_onMotion;
  HoverCallback m_onEnter;
  HoverCallback m_onLeave;
  ThumbnailService* m_thumbnails = nullptr;
};
