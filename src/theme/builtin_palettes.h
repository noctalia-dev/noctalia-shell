#pragma once

#include "theme/fixed_palette.h"

#include <span>
#include <string_view>

namespace noctalia::theme {

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
