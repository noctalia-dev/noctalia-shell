#pragma once

#include "render/core/color.h"

struct Palette {
  Color primary;
  Color onPrimary;
  Color secondary;
  Color onSecondary;
  Color tertiary;
  Color onTertiary;
  Color error;
  Color onError;
  Color surface;
  Color onSurface;
  Color surfaceVariant;
  Color onSurfaceVariant;
  Color outline;
  Color shadow;
  Color hover;
  Color onHover;
};

// Rosepine
inline constexpr Palette palette{
    .primary = hex("#ebbcba"),
    .onPrimary = hex("#191724"),
    .secondary = hex("#9ccfd8"),
    .onSecondary = hex("#191724"),
    .tertiary = hex("#31748f"),
    .onTertiary = hex("#e0def4"),
    .error = hex("#eb6f92"),
    .onError = hex("#191724"),
    .surface = hex("#191724"),
    .onSurface = hex("#e0def4"),
    .surfaceVariant = hex("#26233a"),
    .onSurfaceVariant = hex("#908caa"),
    .outline = hex("#403d52"),
    .shadow = hex("#191724"),
    .hover = hex("#524f67"),
    .onHover = hex("#e0def4"),
};

// Noctalia
// inline constexpr Palette palette{
//     .primary = hex("#fff59b"),
//     .onPrimary = hex("#0e0e43"),
//     .secondary = hex("#a9aefe"),
//     .onSecondary = hex("#0e0e43"),
//     .tertiary = hex("#9BFECE"),
//     .onTertiary = hex("#0e0e43"),
//     .error = hex("#FD4663"),
//     .onError = hex("#0e0e43"),
//     .surface = hex("#070722"),
//     .onSurface = hex("#f3edf7"),
//     .surfaceVariant = hex("#11112d"),
//     .onSurfaceVariant = hex("#7c80b4"),
//     .outline = hex("#21215F"),
//     .shadow = hex("#070722"),
//     .hover = hex("#9BFECE"),
//     .onHover = hex("#0e0e43"),
// };
