#include "ui/palette.h"

#include "theme/builtin_palettes.h"

#include <cctype>
#include <string>

Palette palette = noctalia::theme::findBuiltinPalette("Noctalia")->dark;

namespace {

  std::string normalizedRoleToken(std::string_view token) {
    while (!token.empty() && std::isspace(static_cast<unsigned char>(token.front())) != 0) {
      token.remove_prefix(1);
    }
    while (!token.empty() && std::isspace(static_cast<unsigned char>(token.back())) != 0) {
      token.remove_suffix(1);
    }

    std::string normalized(token);
    for (auto& c : normalized) {
      if (c == '-') {
        c = '_';
      } else {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      }
    }
    return normalized;
  }

} // namespace

const Color& resolveColorRole(ColorRole role) noexcept {
  switch (role) {
  case ColorRole::Primary:
    return palette.primary;
  case ColorRole::OnPrimary:
    return palette.onPrimary;
  case ColorRole::Secondary:
    return palette.secondary;
  case ColorRole::OnSecondary:
    return palette.onSecondary;
  case ColorRole::Tertiary:
    return palette.tertiary;
  case ColorRole::OnTertiary:
    return palette.onTertiary;
  case ColorRole::Error:
    return palette.error;
  case ColorRole::OnError:
    return palette.onError;
  case ColorRole::Surface:
    return palette.surface;
  case ColorRole::OnSurface:
    return palette.onSurface;
  case ColorRole::SurfaceVariant:
    return palette.surfaceVariant;
  case ColorRole::OnSurfaceVariant:
    return palette.onSurfaceVariant;
  case ColorRole::Outline:
    return palette.outline;
  case ColorRole::Shadow:
    return palette.shadow;
  case ColorRole::Hover:
    return palette.hover;
  case ColorRole::OnHover:
    return palette.onHover;
  }

  return palette.onSurface;
}

std::optional<ColorRole> colorRoleFromToken(std::string_view token) {
  const std::string normalized = normalizedRoleToken(token);
  if (normalized == "primary") {
    return ColorRole::Primary;
  }
  if (normalized == "on_primary") {
    return ColorRole::OnPrimary;
  }
  if (normalized == "secondary") {
    return ColorRole::Secondary;
  }
  if (normalized == "on_secondary") {
    return ColorRole::OnSecondary;
  }
  if (normalized == "tertiary") {
    return ColorRole::Tertiary;
  }
  if (normalized == "on_tertiary") {
    return ColorRole::OnTertiary;
  }
  if (normalized == "error") {
    return ColorRole::Error;
  }
  if (normalized == "on_error") {
    return ColorRole::OnError;
  }
  if (normalized == "surface") {
    return ColorRole::Surface;
  }
  if (normalized == "on_surface") {
    return ColorRole::OnSurface;
  }
  if (normalized == "surface_variant") {
    return ColorRole::SurfaceVariant;
  }
  if (normalized == "surface_secondary") {
    return ColorRole::Secondary;
  }
  if (normalized == "on_surface_variant") {
    return ColorRole::OnSurfaceVariant;
  }
  if (normalized == "outline") {
    return ColorRole::Outline;
  }
  if (normalized == "shadow") {
    return ColorRole::Shadow;
  }
  if (normalized == "hover") {
    return ColorRole::Hover;
  }
  if (normalized == "on_hover") {
    return ColorRole::OnHover;
  }
  return std::nullopt;
}

ThemeColor roleColor(ColorRole role, float alpha) noexcept {
  return ThemeColor{.role = role, .fixed = clearColor(), .alpha = alpha};
}

ThemeColor fixedColor(const Color& color) noexcept {
  return ThemeColor{.role = std::nullopt, .fixed = color, .alpha = 1.0f};
}

Color resolveThemeColor(const ThemeColor& color) noexcept {
  Color resolved = color.role.has_value() ? resolveColorRole(*color.role) : color.fixed;
  resolved.a *= color.alpha;
  return resolved;
}

Signal<>& paletteChanged() {
  static Signal<> signal;
  return signal;
}

void setPalette(const Palette& p) {
  if (palette == p) {
    return;
  }
  palette = p;
  paletteChanged().emit();
}

Palette lerpPalette(const Palette& a, const Palette& b, float t) {
  return Palette{
      .primary = lerpColor(a.primary, b.primary, t),
      .onPrimary = lerpColor(a.onPrimary, b.onPrimary, t),
      .secondary = lerpColor(a.secondary, b.secondary, t),
      .onSecondary = lerpColor(a.onSecondary, b.onSecondary, t),
      .tertiary = lerpColor(a.tertiary, b.tertiary, t),
      .onTertiary = lerpColor(a.onTertiary, b.onTertiary, t),
      .error = lerpColor(a.error, b.error, t),
      .onError = lerpColor(a.onError, b.onError, t),
      .surface = lerpColor(a.surface, b.surface, t),
      .onSurface = lerpColor(a.onSurface, b.onSurface, t),
      .surfaceVariant = lerpColor(a.surfaceVariant, b.surfaceVariant, t),
      .onSurfaceVariant = lerpColor(a.onSurfaceVariant, b.onSurfaceVariant, t),
      .outline = lerpColor(a.outline, b.outline, t),
      .shadow = lerpColor(a.shadow, b.shadow, t),
      .hover = lerpColor(a.hover, b.hover, t),
      .onHover = lerpColor(a.onHover, b.onHover, t),
  };
}
