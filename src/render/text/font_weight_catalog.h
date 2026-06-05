#pragma once

#include "render/core/renderer.h"

#include <string_view>
#include <vector>

namespace text {

  void invalidateFontWeightCatalogCache();

  [[nodiscard]] bool fontFamilySupportsVariableWeight(std::string_view fontFamily);

  [[nodiscard]] std::vector<FontWeight> availableLabelFontWeights(std::string_view fontFamily);

} // namespace text
