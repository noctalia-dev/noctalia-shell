#pragma once

#include "theme/palette.h"
#include "ui/palette.h"

#include <unordered_map>

namespace noctalia::theme {

  using TokenMap = std::unordered_map<std::string, uint32_t>;

  TokenMap expandFixedPaletteMode(const ::Palette& palette, bool isDark);
  GeneratedPalette expandFixedPalettes(const ::Palette& dark, const ::Palette& light);
  ::Palette mapGeneratedPaletteMode(const TokenMap& tokens);

} // namespace noctalia::theme
