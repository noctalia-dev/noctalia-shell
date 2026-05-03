#pragma once

#include "theme/palette.h"
#include "ui/palette.h"

#include <unordered_map>

namespace noctalia::theme {

  using TokenMap = std::unordered_map<std::string, uint32_t>;

  struct TerminalAnsiColors {
    ::Color black;
    ::Color red;
    ::Color green;
    ::Color yellow;
    ::Color blue;
    ::Color magenta;
    ::Color cyan;
    ::Color white;
  };

  struct TerminalPalette {
    TerminalAnsiColors normal;
    TerminalAnsiColors bright;
    ::Color foreground;
    ::Color background;
    ::Color selectionFg;
    ::Color selectionBg;
    ::Color cursorText;
    ::Color cursor;
  };

  TokenMap expandFixedPaletteMode(const ::Palette& palette, bool isDark);
  GeneratedPalette expandFixedPalettes(const ::Palette& dark, const ::Palette& light);
  ::Palette mapGeneratedPaletteMode(const TokenMap& tokens);

  void applyTerminalPalette(TokenMap& tokens, const TerminalPalette& terminal);
  void synthesizeTerminalPaletteTokens(TokenMap& tokens);
  void synthesizeTerminalPaletteTokens(GeneratedPalette& palette);

} // namespace noctalia::theme
