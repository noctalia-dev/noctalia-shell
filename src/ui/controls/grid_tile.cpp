#include "ui/controls/grid_tile.h"

#include "render/core/renderer.h"

#include <algorithm>

void GridTile::layout(Renderer& renderer) {
  const float aw = width();
  const float ah = height();
  if (aw > 0.0f) {
    Flex::setMinWidth(aw);
  }
  if (ah > 0.0f) {
    Flex::setMinHeight(ah);
  }
  Flex::layout(renderer);
  Flex::setMinWidth(0.0f);
  Flex::setMinHeight(0.0f);
  if (aw > 0.0f || ah > 0.0f) {
    Flex::setSize(std::max(width(), aw), std::max(height(), ah));
  }
}
