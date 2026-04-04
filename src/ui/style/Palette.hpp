#pragma once

#include "render/core/Color.hpp"

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

inline constexpr Palette palette{
    .primary = hex("#fff59b"),
    .onPrimary = hex("#0e0e43"),
    .secondary = hex("#a9aefe"),
    .onSecondary = hex("#0e0e43"),
    .tertiary = hex("#9BFECE"),
    .onTertiary = hex("#0e0e43"),
    .error = hex("#FD4663"),
    .onError = hex("#0e0e43"),
    .surface = hex("#070722"),
    .onSurface = hex("#f3edf7"),
    .surfaceVariant = hex("#11112d"),
    .onSurfaceVariant = hex("#7c80b4"),
    .outline= hex("#21215F"),
    .shadow= hex("#070722"),
    .hover= hex("#9BFECE"),
    .onHover= hex("#0e0e43"),
};
