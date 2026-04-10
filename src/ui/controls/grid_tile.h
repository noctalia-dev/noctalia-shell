#pragma once

#include "ui/controls/flex.h"

class Renderer;

// Flex that fills its GridView cell. Layout temporarily raises min size to the cell,
// then clears mins to zero (do not rely on persistent setMinWidth/setMinHeight here).
class GridTile : public Flex {
public:
  void layout(Renderer& renderer) override;
};
