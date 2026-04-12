#pragma once

#include "ui/palette.h"

#include <span>
#include <string_view>

namespace noctalia::theme {

  struct BuiltinScheme {
    std::string_view name;
    Palette dark;
    Palette light;
  };

  std::span<const BuiltinScheme> builtinSchemes();

  const BuiltinScheme* findBuiltinScheme(std::string_view name);

} // namespace noctalia::theme
