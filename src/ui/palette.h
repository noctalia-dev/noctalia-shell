#pragma once

#include "render/core/color.h"
#include "ui/signal.h"

#include <optional>

enum class ColorRole : std::uint8_t {
  Primary,
  OnPrimary,
  Secondary,
  OnSecondary,
  Tertiary,
  OnTertiary,
  Error,
  OnError,
  Surface,
  OnSurface,
  SurfaceVariant,
  OnSurfaceVariant,
  Outline,
  Shadow,
  Hover,
  OnHover,
};

[[nodiscard]] constexpr Color clearColor() noexcept { return rgba(0.0f, 0.0f, 0.0f, 0.0f); }

struct ThemeColor {
  std::optional<ColorRole> role;
  Color fixed = clearColor();
  float alpha = 1.0f;
};

constexpr bool operator==(const ThemeColor& a, const ThemeColor& b) noexcept {
  return a.role == b.role && a.fixed == b.fixed && a.alpha == b.alpha;
}

[[nodiscard]] constexpr ThemeColor clearThemeColor() noexcept {
  return ThemeColor{.role = std::nullopt, .fixed = clearColor(), .alpha = 1.0f};
}

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

constexpr bool operator==(const Palette& lhs, const Palette& rhs) noexcept {
  return lhs.primary == rhs.primary && lhs.onPrimary == rhs.onPrimary && lhs.secondary == rhs.secondary &&
         lhs.onSecondary == rhs.onSecondary && lhs.tertiary == rhs.tertiary && lhs.onTertiary == rhs.onTertiary &&
         lhs.error == rhs.error && lhs.onError == rhs.onError && lhs.surface == rhs.surface &&
         lhs.onSurface == rhs.onSurface && lhs.surfaceVariant == rhs.surfaceVariant &&
         lhs.onSurfaceVariant == rhs.onSurfaceVariant && lhs.outline == rhs.outline && lhs.shadow == rhs.shadow &&
         lhs.hover == rhs.hover && lhs.onHover == rhs.onHover;
}

extern Palette palette;

[[nodiscard]] const Color& resolveColorRole(ColorRole role) noexcept;
[[nodiscard]] ThemeColor roleColor(ColorRole role, float alpha = 1.0f) noexcept;
[[nodiscard]] ThemeColor fixedColor(const Color& color) noexcept;
[[nodiscard]] Color resolveThemeColor(const ThemeColor& color) noexcept;

void setPalette(const Palette& p);

// Fired after setPalette() writes. Controls subscribe in their constructor
// and re-apply palette-derived colors to their scene nodes on each emit.
Signal<>& paletteChanged();

// Linearly interpolates each field of two palettes in sRGB space. Used by
// ThemeService to drive smooth cross-fade transitions on theme changes.
Palette lerpPalette(const Palette& a, const Palette& b, float t);
