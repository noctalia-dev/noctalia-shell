#pragma once

#include "theme/palette.h"
#include "ui/palette.h"

#include <span>
#include <string_view>

namespace noctalia::theme {

  struct TerminalAnsiColors {
    Color black;
    Color red;
    Color green;
    Color yellow;
    Color blue;
    Color magenta;
    Color cyan;
    Color white;
  };

  struct TerminalPalette {
    TerminalAnsiColors normal;
    TerminalAnsiColors bright;
    Color foreground;
    Color background;
    Color selectionFg;
    Color selectionBg;
    Color cursorText;
    Color cursor;
  };

  struct BuiltinPalette {
    std::string_view name;
    Palette dark;
    Palette light;
    TerminalPalette darkTerminal;
    TerminalPalette lightTerminal;
  };

  std::span<const BuiltinPalette> builtinPalettes();

  const BuiltinPalette* findBuiltinPalette(std::string_view name);
  GeneratedPalette expandBuiltinPalette(const BuiltinPalette& palette);

} // namespace noctalia::theme
