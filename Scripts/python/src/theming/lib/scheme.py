"""
Predefined scheme expansion - Convert 14-color schemes to full palette.

This module expands predefined color schemes (like Tokyo-Night) from their
14 core colors to the full 48-color palette used by templates.

Input format (14 colors):
    mPrimary, mOnPrimary, mSecondary, mOnSecondary, mTertiary, mOnTertiary,
    mError, mOnError, mSurface, mOnSurface, mSurfaceVariant, mOnSurfaceVariant,
    mOutline, mHover

Output: Full 48-color palette matching generate_theme() output.
"""

from typing import Literal

from .color import Color
from .contrast import ensure_contrast

ThemeMode = Literal["dark", "light"]


def _hex_to_color(hex_str: str) -> Color:
    """Convert hex string to Color object."""
    hex_str = hex_str.lstrip("#")
    r = int(hex_str[0:2], 16)
    g = int(hex_str[2:4], 16)
    b = int(hex_str[4:6], 16)
    return Color(r, g, b)


def _make_container_dark(base: Color) -> Color:
    """Generate container color for dark mode."""
    h, s, l = base.to_hsl()
    return Color.from_hsl(h, min(s + 0.15, 1.0), max(l - 0.35, 0.15))


def _make_container_light(base: Color) -> Color:
    """Generate container color for light mode."""
    h, s, l = base.to_hsl()
    return Color.from_hsl(h, max(s - 0.20, 0.30), min(l + 0.35, 0.85))


def _make_fixed_dark(base: Color) -> tuple[Color, Color]:
    """Generate fixed and fixed_dim colors for dark mode."""
    h, s, _ = base.to_hsl()
    fixed = Color.from_hsl(h, max(s, 0.70), 0.85)
    fixed_dim = Color.from_hsl(h, max(s, 0.65), 0.75)
    return fixed, fixed_dim


def _make_fixed_light(base: Color) -> tuple[Color, Color]:
    """Generate fixed and fixed_dim colors for light mode."""
    h, s, _ = base.to_hsl()
    fixed = Color.from_hsl(h, max(s, 0.70), 0.40)
    fixed_dim = Color.from_hsl(h, max(s, 0.65), 0.30)
    return fixed, fixed_dim


def _interpolate_color(c1: Color, c2: Color, t: float) -> Color:
    """Interpolate between two colors. t=0 returns c1, t=1 returns c2."""
    r = int(c1.r + (c2.r - c1.r) * t)
    g = int(c1.g + (c2.g - c1.g) * t)
    b = int(c1.b + (c2.b - c1.b) * t)
    return Color(max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))


def expand_predefined_scheme(scheme_data: dict[str, str], mode: ThemeMode) -> dict[str, str]:
    """
    Expand 14-color predefined scheme to full 48-color palette.

    Args:
        scheme_data: Dictionary with keys like mPrimary, mSecondary, etc.
        mode: "dark" or "light"

    Returns:
        Dictionary with all 48 color names mapped to hex values.
    """
    is_dark = mode == "dark"

    # Parse input colors
    primary = _hex_to_color(scheme_data["mPrimary"])
    on_primary = _hex_to_color(scheme_data["mOnPrimary"])
    secondary = _hex_to_color(scheme_data["mSecondary"])
    on_secondary = _hex_to_color(scheme_data["mOnSecondary"])
    tertiary = _hex_to_color(scheme_data["mTertiary"])
    on_tertiary = _hex_to_color(scheme_data["mOnTertiary"])
    error = _hex_to_color(scheme_data["mError"])
    on_error = _hex_to_color(scheme_data["mOnError"])
    surface = _hex_to_color(scheme_data["mSurface"])
    on_surface = _hex_to_color(scheme_data["mOnSurface"])
    surface_variant = _hex_to_color(scheme_data["mSurfaceVariant"])
    on_surface_variant = _hex_to_color(scheme_data["mOnSurfaceVariant"])
    outline_raw = _hex_to_color(scheme_data["mOutline"])
    shadow = _hex_to_color(scheme_data.get("mShadow", scheme_data["mSurface"]))

    # Generate container colors
    if is_dark:
        primary_container = _make_container_dark(primary)
        secondary_container = _make_container_dark(secondary)
        tertiary_container = _make_container_dark(tertiary)
        error_container = _make_container_dark(error)
    else:
        primary_container = _make_container_light(primary)
        secondary_container = _make_container_light(secondary)
        tertiary_container = _make_container_light(tertiary)
        error_container = _make_container_light(error)

    # Generate "on container" colors with proper contrast
    primary_h, primary_s, _ = primary.to_hsl()
    secondary_h, secondary_s, _ = secondary.to_hsl()
    tertiary_h, tertiary_s, _ = tertiary.to_hsl()
    error_h, error_s, _ = error.to_hsl()

    if is_dark:
        # Light text on dark containers
        on_primary_container = ensure_contrast(
            Color.from_hsl(primary_h, primary_s, 0.90), primary_container, 4.5
        )
        on_secondary_container = ensure_contrast(
            Color.from_hsl(secondary_h, secondary_s, 0.90), secondary_container, 4.5
        )
        on_tertiary_container = ensure_contrast(
            Color.from_hsl(tertiary_h, tertiary_s, 0.90), tertiary_container, 4.5
        )
        on_error_container = ensure_contrast(
            Color.from_hsl(error_h, error_s, 0.90), error_container, 4.5
        )
    else:
        # Dark text on light containers
        on_primary_container = ensure_contrast(
            Color.from_hsl(primary_h, primary_s, 0.15), primary_container, 4.5
        )
        on_secondary_container = ensure_contrast(
            Color.from_hsl(secondary_h, secondary_s, 0.15), secondary_container, 4.5
        )
        on_tertiary_container = ensure_contrast(
            Color.from_hsl(tertiary_h, tertiary_s, 0.15), tertiary_container, 4.5
        )
        on_error_container = ensure_contrast(
            Color.from_hsl(error_h, error_s, 0.15), error_container, 4.5
        )

    # Generate fixed colors
    if is_dark:
        primary_fixed, primary_fixed_dim = _make_fixed_dark(primary)
        secondary_fixed, secondary_fixed_dim = _make_fixed_dark(secondary)
        tertiary_fixed, tertiary_fixed_dim = _make_fixed_dark(tertiary)
    else:
        primary_fixed, primary_fixed_dim = _make_fixed_light(primary)
        secondary_fixed, secondary_fixed_dim = _make_fixed_light(secondary)
        tertiary_fixed, tertiary_fixed_dim = _make_fixed_light(tertiary)

    # Generate "on fixed" colors
    if is_dark:
        on_primary_fixed = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.15), primary_fixed, 4.5
        )
        on_primary_fixed_variant = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.20), primary_fixed_dim, 4.5
        )
        on_secondary_fixed = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.15), secondary_fixed, 4.5
        )
        on_secondary_fixed_variant = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.20), secondary_fixed_dim, 4.5
        )
        on_tertiary_fixed = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.15), tertiary_fixed, 4.5
        )
        on_tertiary_fixed_variant = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.20), tertiary_fixed_dim, 4.5
        )
    else:
        on_primary_fixed = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.90), primary_fixed, 4.5
        )
        on_primary_fixed_variant = ensure_contrast(
            Color.from_hsl(primary_h, 0.15, 0.85), primary_fixed_dim, 4.5
        )
        on_secondary_fixed = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.90), secondary_fixed, 4.5
        )
        on_secondary_fixed_variant = ensure_contrast(
            Color.from_hsl(secondary_h, 0.15, 0.85), secondary_fixed_dim, 4.5
        )
        on_tertiary_fixed = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.90), tertiary_fixed, 4.5
        )
        on_tertiary_fixed_variant = ensure_contrast(
            Color.from_hsl(tertiary_h, 0.15, 0.85), tertiary_fixed_dim, 4.5
        )

    # Generate surface containers using mSurfaceVariant as the middle container
    # This respects the scheme author's color choices
    surface_h, surface_s, surface_l = surface.to_hsl()
    sv_h, sv_s, sv_l = surface_variant.to_hsl()

    # surface_container = mSurfaceVariant (direct assignment)
    surface_container = surface_variant

    if is_dark:
        # Dark mode: surface is darkest, surface_variant is the middle container
        # Lower containers interpolate between surface and surface_variant
        surface_container_lowest = _interpolate_color(surface, surface_variant, 0.2)
        surface_container_low = _interpolate_color(surface, surface_variant, 0.5)
        # Higher containers go beyond surface_variant (lighter)
        surface_container_high = Color.from_hsl(sv_h, sv_s, min(sv_l + 0.04, 0.40))
        surface_container_highest = Color.from_hsl(sv_h, sv_s, min(sv_l + 0.08, 0.45))
        # Dim is darker than surface, bright is lighter than highest container
        surface_dim = Color.from_hsl(surface_h, surface_s, max(surface_l - 0.04, 0.02))
        surface_bright = Color.from_hsl(sv_h, sv_s, min(sv_l + 0.12, 0.50))
    else:
        # Light mode: surface is lightest, surface_variant is the middle container
        # Lower containers interpolate between surface and surface_variant
        surface_container_lowest = _interpolate_color(surface, surface_variant, 0.2)
        surface_container_low = _interpolate_color(surface, surface_variant, 0.5)
        # Higher containers go beyond surface_variant (darker)
        surface_container_high = Color.from_hsl(sv_h, sv_s, max(sv_l - 0.04, 0.60))
        surface_container_highest = Color.from_hsl(sv_h, sv_s, max(sv_l - 0.08, 0.55))
        # Dim is darker than highest, bright is lighter than surface
        surface_dim = Color.from_hsl(sv_h, sv_s, max(sv_l - 0.12, 0.50))
        surface_bright = Color.from_hsl(surface_h, surface_s, min(surface_l + 0.03, 0.98))

    # Ensure outline has sufficient contrast against surface (3:1 minimum for UI)
    outline = ensure_contrast(outline_raw, surface, 3.0)

    # Generate outline variant
    outline_h, outline_s, outline_l = outline.to_hsl()
    if is_dark:
        outline_variant = Color.from_hsl(outline_h, outline_s, max(outline_l - 0.15, 0.1))
    else:
        outline_variant = Color.from_hsl(outline_h, outline_s, min(outline_l + 0.15, 0.9))

    # Scrim is always black
    scrim = Color(0, 0, 0)

    # Inverse colors
    if is_dark:
        inverse_surface = Color.from_hsl(surface_h, 0.08, 0.90)
        inverse_on_surface = Color.from_hsl(surface_h, 0.05, 0.15)
        inverse_primary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.40)
    else:
        inverse_surface = Color.from_hsl(surface_h, 0.08, 0.15)
        inverse_on_surface = Color.from_hsl(surface_h, 0.05, 0.90)
        inverse_primary = Color.from_hsl(primary_h, max(primary_s * 0.8, 0.5), 0.70)

    # Background is same as surface in MD3
    background = surface
    on_background = on_surface

    return {
        # Primary
        "primary": primary.to_hex(),
        "on_primary": on_primary.to_hex(),
        "primary_container": primary_container.to_hex(),
        "on_primary_container": on_primary_container.to_hex(),
        "primary_fixed": primary_fixed.to_hex(),
        "primary_fixed_dim": primary_fixed_dim.to_hex(),
        "on_primary_fixed": on_primary_fixed.to_hex(),
        "on_primary_fixed_variant": on_primary_fixed_variant.to_hex(),
        # Secondary
        "secondary": secondary.to_hex(),
        "on_secondary": on_secondary.to_hex(),
        "secondary_container": secondary_container.to_hex(),
        "on_secondary_container": on_secondary_container.to_hex(),
        "secondary_fixed": secondary_fixed.to_hex(),
        "secondary_fixed_dim": secondary_fixed_dim.to_hex(),
        "on_secondary_fixed": on_secondary_fixed.to_hex(),
        "on_secondary_fixed_variant": on_secondary_fixed_variant.to_hex(),
        # Tertiary
        "tertiary": tertiary.to_hex(),
        "on_tertiary": on_tertiary.to_hex(),
        "tertiary_container": tertiary_container.to_hex(),
        "on_tertiary_container": on_tertiary_container.to_hex(),
        "tertiary_fixed": tertiary_fixed.to_hex(),
        "tertiary_fixed_dim": tertiary_fixed_dim.to_hex(),
        "on_tertiary_fixed": on_tertiary_fixed.to_hex(),
        "on_tertiary_fixed_variant": on_tertiary_fixed_variant.to_hex(),
        # Error
        "error": error.to_hex(),
        "on_error": on_error.to_hex(),
        "error_container": error_container.to_hex(),
        "on_error_container": on_error_container.to_hex(),
        # Surface
        "surface": surface.to_hex(),
        "on_surface": on_surface.to_hex(),
        "surface_variant": surface_variant.to_hex(),
        "on_surface_variant": on_surface_variant.to_hex(),
        "surface_dim": surface_dim.to_hex(),
        "surface_bright": surface_bright.to_hex(),
        # Surface containers
        "surface_container_lowest": surface_container_lowest.to_hex(),
        "surface_container_low": surface_container_low.to_hex(),
        "surface_container": surface_container.to_hex(),
        "surface_container_high": surface_container_high.to_hex(),
        "surface_container_highest": surface_container_highest.to_hex(),
        # Outline and other
        "outline": outline.to_hex(),
        "outline_variant": outline_variant.to_hex(),
        "shadow": shadow.to_hex(),
        "scrim": scrim.to_hex(),
        # Inverse
        "inverse_surface": inverse_surface.to_hex(),
        "inverse_on_surface": inverse_on_surface.to_hex(),
        "inverse_primary": inverse_primary.to_hex(),
        # Background
        "background": background.to_hex(),
        "on_background": on_background.to_hex(),
    }


def inject_terminal_colors(result: dict[str, str], scheme_mode_data: dict) -> dict[str, str]:
    """Flatten scheme's terminal section into template-ready color keys.

    Adds keys like terminal_foreground, terminal_normal_black, terminal_bright_red, etc.
    so predefined terminal templates can reference them as
    {{colors.terminal_foreground.default.hex_stripped}}.

    Args:
        result: Expanded color palette dict to augment.
        scheme_mode_data: Raw scheme JSON mode data (e.g., scheme_data["dark"]).

    Returns:
        The same result dict with terminal_ keys added.
    """
    terminal = scheme_mode_data.get("terminal")
    if not terminal:
        return result

    # Map of JSON keys to flattened key names
    direct_keys = {
        "foreground": "terminal_foreground",
        "background": "terminal_background",
        "cursor": "terminal_cursor",
        "cursorText": "terminal_cursor_text",
        "selectionFg": "terminal_selection_fg",
        "selectionBg": "terminal_selection_bg",
    }

    for json_key, flat_key in direct_keys.items():
        if json_key in terminal:
            result[flat_key] = terminal[json_key]

    # ANSI normal/bright color groups
    for group in ("normal", "bright"):
        if group in terminal:
            for name, hex_val in terminal[group].items():
                result[f"terminal_{group}_{name}"] = hex_val

    return result
