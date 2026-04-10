#pragma once

#include "theme/color.h"

namespace noctalia::theme {

  double relativeLuminance(int r, int g, int b);
  double contrastRatio(const Color& a, const Color& b);
  bool isDark(const Color& c);

  // Binary-search the foreground's HSL lightness toward black or white until
  // the WCAG contrast ratio against `background` meets `minRatio`.
  // preferLight: -1 = darken, +1 = lighten, 0 = auto (lighten if bg is dark).
  Color ensureContrast(const Color& foreground, const Color& background, double minRatio = 4.5, int preferLight = 0);

} // namespace noctalia::theme
