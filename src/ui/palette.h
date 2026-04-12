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
