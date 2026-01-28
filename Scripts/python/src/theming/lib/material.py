"""
Material Design 3 color scheme implementation.

This module provides scheme classes for generating MD3 color schemes
from a source color using the HCT color space.

Supported schemes (matching Matugen):
- SchemeTonalSpot: Default Android 12-13 scheme, mid-vibrancy
- SchemeFruitSalad: Bold/playful with -50° hue rotation
- SchemeRainbow: Chromatic accents with grayscale neutrals
- SchemeContent: Preserves source color's chroma
"""

from .hct import Hct, TonalPalette, TemperatureCache, fix_if_disliked


# =============================================================================
# Tone Values (shared across all schemes)
# =============================================================================

# Tone values for Material Design 3 (dark theme)
DARK_TONES = {
    'primary': 80,
    'on_primary': 20,
    'primary_container': 30,
    'on_primary_container': 90,
    'secondary': 80,
    'on_secondary': 20,
    'secondary_container': 30,
    'on_secondary_container': 90,
    'tertiary': 80,
    'on_tertiary': 20,
    'tertiary_container': 30,
    'on_tertiary_container': 90,
    'error': 80,
    'on_error': 20,
    'error_container': 30,
    'on_error_container': 90,
    'surface': 6,
    'on_surface': 90,
    'surface_variant': 30,
    'on_surface_variant': 80,
    'surface_container_lowest': 4,
    'surface_container_low': 10,
    'surface_container': 12,
    'surface_container_high': 17,
    'surface_container_highest': 22,
    'outline': 60,
    'outline_variant': 30,
    'shadow': 0,
    'scrim': 0,
    'inverse_surface': 90,
    'inverse_on_surface': 20,
    'inverse_primary': 40,
}

# Tone values for Material Design 3 (light theme)
LIGHT_TONES = {
    'primary': 40,
    'on_primary': 100,
    'primary_container': 90,
    'on_primary_container': 10,
    'secondary': 40,
    'on_secondary': 100,
    'secondary_container': 90,
    'on_secondary_container': 10,
    'tertiary': 40,
    'on_tertiary': 100,
    'tertiary_container': 90,
    'on_tertiary_container': 10,
    'error': 40,
    'on_error': 100,
    'error_container': 90,
    'on_error_container': 10,
    'surface': 98,
    'on_surface': 10,
    'surface_variant': 90,
    'on_surface_variant': 30,
    'surface_container_lowest': 100,
    'surface_container_low': 96,
    'surface_container': 94,
    'surface_container_high': 92,
    'surface_container_highest': 90,
    'outline': 50,
    'outline_variant': 80,
    'shadow': 0,
    'scrim': 0,
    'inverse_surface': 20,
    'inverse_on_surface': 95,
    'inverse_primary': 80,
}

# Monochrome scheme uses different tone values (from material-colors library)
# Primary/tertiary get special treatment for higher contrast in grayscale
MONOCHROME_DARK_TONES = {
    **DARK_TONES,
    'primary': 100,              # White (was 80)
    'on_primary': 10,            # Near-black (was 20)
    'primary_container': 85,     # Light gray (was 30)
    'on_primary_container': 0,   # Black (was 90)
    'tertiary': 90,              # Light gray (was 80)
    'on_tertiary': 10,           # Near-black (was 20)
    'tertiary_container': 60,    # Mid gray (was 30)
    'on_tertiary_container': 0,  # Black (was 90)
    'secondary_container': 30,   # Same as normal
}

MONOCHROME_LIGHT_TONES = {
    **LIGHT_TONES,
    'primary': 0,                # Black (was 40)
    'on_primary': 90,            # Light gray (was 100)
    'primary_container': 25,     # Dark gray (was 90)
    'on_primary_container': 100, # White (was 10)
    'tertiary': 25,              # Dark gray (was 40)
    'on_tertiary': 90,           # Light gray (was 100)
    'tertiary_container': 49,    # Mid gray (was 90)
    'on_tertiary_container': 100, # White (was 10)
    'secondary_container': 90,   # Same as normal
}


# =============================================================================
# Base Scheme Class
# =============================================================================

class _BaseScheme:
    """Base class for all Material Design 3 schemes."""

    # Error palette is the same for all schemes
    error_palette: TonalPalette

    def __init__(self, source_color: Hct):
        """Initialize with source color. Subclasses must set palettes."""
        self.source = source_color
        self.error_palette = TonalPalette(25.0, 84.0)  # Material red

    @classmethod
    def from_rgb(cls, r: int, g: int, b: int) -> '_BaseScheme':
        """Create scheme from RGB color."""
        return cls(Hct.from_rgb(r, g, b))

    @classmethod
    def from_hex(cls, hex_color: str) -> '_BaseScheme':
        """Create scheme from hex color string."""
        hex_color = hex_color.lstrip('#')
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)
        return cls.from_rgb(r, g, b)

    def get_dark_scheme(self) -> dict[str, str]:
        """Generate dark theme color dictionary."""
        return self._generate_scheme(is_dark=True)

    def get_light_scheme(self) -> dict[str, str]:
        """Generate light theme color dictionary."""
        return self._generate_scheme(is_dark=False)

    def _generate_scheme(self, is_dark: bool) -> dict[str, str]:
        """Generate scheme with appropriate tone values."""
        tones = DARK_TONES if is_dark else LIGHT_TONES

        scheme = {
            # Primary colors
            'primary': self.primary_palette.get_hex(tones['primary']),
            'on_primary': self.primary_palette.get_hex(tones['on_primary']),
            'primary_container': self.primary_palette.get_hex(tones['primary_container']),
            'on_primary_container': self.primary_palette.get_hex(tones['on_primary_container']),

            # Surface tint (same as primary, used for M3 elevation tinting)
            'surface_tint': self.primary_palette.get_hex(tones['primary']),

            # Secondary colors
            'secondary': self.secondary_palette.get_hex(tones['secondary']),
            'on_secondary': self.secondary_palette.get_hex(tones['on_secondary']),
            'secondary_container': self.secondary_palette.get_hex(tones['secondary_container']),
            'on_secondary_container': self.secondary_palette.get_hex(tones['on_secondary_container']),

            # Tertiary colors
            'tertiary': self.tertiary_palette.get_hex(tones['tertiary']),
            'on_tertiary': self.tertiary_palette.get_hex(tones['on_tertiary']),
            'tertiary_container': self.tertiary_palette.get_hex(tones['tertiary_container']),
            'on_tertiary_container': self.tertiary_palette.get_hex(tones['on_tertiary_container']),

            # Error colors
            'error': self.error_palette.get_hex(tones['error']),
            'on_error': self.error_palette.get_hex(tones['on_error']),
            'error_container': self.error_palette.get_hex(tones['error_container']),
            'on_error_container': self.error_palette.get_hex(tones['on_error_container']),

            # Surface colors
            'surface': self.neutral_palette.get_hex(tones['surface']),
            'on_surface': self.neutral_palette.get_hex(tones['on_surface']),
            'surface_variant': self.neutral_variant_palette.get_hex(tones['surface_variant']),
            'on_surface_variant': self.neutral_variant_palette.get_hex(tones['on_surface_variant']),

            # Surface containers
            'surface_container_lowest': self.neutral_palette.get_hex(tones['surface_container_lowest']),
            'surface_container_low': self.neutral_palette.get_hex(tones['surface_container_low']),
            'surface_container': self.neutral_palette.get_hex(tones['surface_container']),
            'surface_container_high': self.neutral_palette.get_hex(tones['surface_container_high']),
            'surface_container_highest': self.neutral_palette.get_hex(tones['surface_container_highest']),

            # Outline and other
            'outline': self.neutral_variant_palette.get_hex(tones['outline']),
            'outline_variant': self.neutral_variant_palette.get_hex(tones['outline_variant']),
            'shadow': self.neutral_palette.get_hex(tones['shadow']),
            'scrim': self.neutral_palette.get_hex(tones['scrim']),

            # Inverse colors
            'inverse_surface': self.neutral_palette.get_hex(tones['inverse_surface']),
            'inverse_on_surface': self.neutral_palette.get_hex(tones['inverse_on_surface']),
            'inverse_primary': self.primary_palette.get_hex(tones['inverse_primary']),

            # Background (alias for surface)
            'background': self.neutral_palette.get_hex(tones['surface']),
            'on_background': self.neutral_palette.get_hex(tones['on_surface']),

            # Surface dim and bright
            'surface_dim': self.neutral_palette.get_hex(87 if not is_dark else 6),
            'surface_bright': self.neutral_palette.get_hex(98 if not is_dark else 24),

            # Fixed colors - consistent across light/dark modes (MD3 spec)
            'primary_fixed': self.primary_palette.get_hex(90),
            'primary_fixed_dim': self.primary_palette.get_hex(80),
            'on_primary_fixed': self.primary_palette.get_hex(10),
            'on_primary_fixed_variant': self.primary_palette.get_hex(30),

            'secondary_fixed': self.secondary_palette.get_hex(90),
            'secondary_fixed_dim': self.secondary_palette.get_hex(80),
            'on_secondary_fixed': self.secondary_palette.get_hex(10),
            'on_secondary_fixed_variant': self.secondary_palette.get_hex(30),

            'tertiary_fixed': self.tertiary_palette.get_hex(90),
            'tertiary_fixed_dim': self.tertiary_palette.get_hex(80),
            'on_tertiary_fixed': self.tertiary_palette.get_hex(10),
            'on_tertiary_fixed_variant': self.tertiary_palette.get_hex(30),
        }

        return scheme


# =============================================================================
# Scheme Implementations
# =============================================================================

class SchemeTonalSpot(_BaseScheme):
    """
    Tonal Spot scheme - the default Android 12-13 Material You scheme.

    Uses fixed chroma values for consistent, harmonious palettes:
    - Primary: source hue, chroma 48
    - Secondary: source hue, chroma 16
    - Tertiary: hue +60°, chroma 24
    - Neutrals: low chroma (tinted with source hue)
    """

    def __init__(self, source_color: Hct):
        super().__init__(source_color)

        # Primary: source hue with fixed chroma 48
        self.primary_palette = TonalPalette(source_color.hue, 48.0)

        # Secondary: source hue with lower chroma 16
        self.secondary_palette = TonalPalette(source_color.hue, 16.0)

        # Tertiary: 60° hue rotation with chroma 24
        tertiary_hue = (source_color.hue + 60.0) % 360.0
        self.tertiary_palette = TonalPalette(tertiary_hue, 24.0)

        # Neutral: source hue with very low chroma (tinted grays)
        self.neutral_palette = TonalPalette(source_color.hue, 4.0)

        # Neutral variant: slightly more chroma for contrast
        self.neutral_variant_palette = TonalPalette(source_color.hue, 8.0)


class SchemeFruitSalad(_BaseScheme):
    """
    Fruit Salad scheme - bold, playful theme with hue rotation.

    Designed for expressive, colorful themes:
    - Primary: hue -50°, chroma 48
    - Secondary: hue -50°, chroma 36
    - Tertiary: source hue (original), chroma 36
    - Neutrals: tinted (chroma 10-16)
    """

    def __init__(self, source_color: Hct):
        super().__init__(source_color)

        # Rotate hue by -50° for primary and secondary
        rotated_hue = (source_color.hue - 50.0) % 360.0

        # Primary: rotated hue with chroma 48
        self.primary_palette = TonalPalette(rotated_hue, 48.0)

        # Secondary: rotated hue with chroma 36
        self.secondary_palette = TonalPalette(rotated_hue, 36.0)

        # Tertiary: original source hue with chroma 36
        self.tertiary_palette = TonalPalette(source_color.hue, 36.0)

        # Neutral: source hue with higher chroma (tinted)
        self.neutral_palette = TonalPalette(source_color.hue, 10.0)

        # Neutral variant: even more tinted
        self.neutral_variant_palette = TonalPalette(source_color.hue, 16.0)


class SchemeRainbow(_BaseScheme):
    """
    Rainbow scheme - chromatic accents with grayscale neutrals.

    Same structure as Tonal Spot but with pure grayscale neutrals:
    - Primary: source hue, chroma 48
    - Secondary: source hue, chroma 16
    - Tertiary: hue +60°, chroma 24
    - Neutrals: pure grayscale (chroma 0)
    """

    def __init__(self, source_color: Hct):
        super().__init__(source_color)

        # Primary: source hue with fixed chroma 48
        self.primary_palette = TonalPalette(source_color.hue, 48.0)

        # Secondary: source hue with lower chroma 16
        self.secondary_palette = TonalPalette(source_color.hue, 16.0)

        # Tertiary: 60° hue rotation with chroma 24
        tertiary_hue = (source_color.hue + 60.0) % 360.0
        self.tertiary_palette = TonalPalette(tertiary_hue, 24.0)

        # Neutral: pure grayscale (chroma 0)
        self.neutral_palette = TonalPalette(0.0, 0.0)

        # Neutral variant: also grayscale
        self.neutral_variant_palette = TonalPalette(0.0, 0.0)


class SchemeContent(_BaseScheme):
    """
    Content scheme - preserves source color's chroma.

    This is the Material Design 3 "content" scheme that preserves the source
    color's characteristics while creating harmonious palettes:
    - Primary: source hue and chroma (full preservation)
    - Secondary: same hue, reduced chroma: max(chroma - 32, chroma * 0.5)
    - Tertiary: analogous color from temperature analysis (warm-cool harmony)
    - Neutrals: low chroma (chroma / 8, tinted with source hue)
    """

    def __init__(self, source_color: Hct):
        super().__init__(source_color)

        # Primary: preserve source color's hue and chroma (full preservation)
        self.primary_palette = TonalPalette(source_color.hue, source_color.chroma)

        # Secondary: same hue, reduced chroma
        # Formula from matugen: max(chroma - 32, chroma * 0.5)
        secondary_chroma = max(source_color.chroma - 32.0, source_color.chroma * 0.5)
        self.secondary_palette = TonalPalette(source_color.hue, secondary_chroma)

        # Tertiary: use analogous color from temperature analysis
        # Get 3 analogous colors with 6 divisions, pick the last one (most different)
        temp_cache = TemperatureCache(source_color)
        analogous_colors = temp_cache.analogous(3, 6)
        tertiary_hct = fix_if_disliked(analogous_colors[-1])
        self.tertiary_palette = TonalPalette.from_hct(tertiary_hct)

        # Neutral: source hue, low chroma (chroma / 8)
        neutral_chroma = source_color.chroma / 8.0
        self.neutral_palette = TonalPalette(source_color.hue, neutral_chroma)

        # Neutral variant: slightly more chroma (chroma / 8 + 4)
        neutral_variant_chroma = (source_color.chroma / 8.0) + 4.0
        self.neutral_variant_palette = TonalPalette(source_color.hue, neutral_variant_chroma)


class SchemeMonochrome(_BaseScheme):
    """
    Material Design 3 Monochrome scheme.

    All color palettes use chroma=0.0, producing a pure grayscale theme.
    Only the error color retains saturation for accessibility.

    Uses special tone mappings (different from other M3 schemes) for higher
    contrast in grayscale - e.g., primary is tone 100 (white) in dark mode.

    Palette configuration:
    - Primary: chroma 0.0 (grayscale)
    - Secondary: chroma 0.0 (grayscale)
    - Tertiary: chroma 0.0 (grayscale)
    - Neutral: chroma 0.0 (grayscale)
    - Neutral variant: chroma 0.0 (grayscale)
    - Error: hue 25°, chroma 84 (vibrant red)
    """

    def __init__(self, source_color: Hct):
        super().__init__(source_color)

        # All palettes use chroma=0 (grayscale)
        # Source hue is preserved but irrelevant at chroma 0
        self.primary_palette = TonalPalette(source_color.hue, 0.0)
        self.secondary_palette = TonalPalette(source_color.hue, 0.0)
        self.tertiary_palette = TonalPalette(source_color.hue, 0.0)
        self.neutral_palette = TonalPalette(source_color.hue, 0.0)
        self.neutral_variant_palette = TonalPalette(source_color.hue, 0.0)

        # Error palette keeps vibrant red for accessibility
        self.error_palette = TonalPalette(25.0, 84.0)

    def _generate_scheme(self, is_dark: bool) -> dict[str, str]:
        """Generate scheme with monochrome-specific tone values."""
        # Monochrome uses different tones for higher contrast in grayscale
        tones = MONOCHROME_DARK_TONES if is_dark else MONOCHROME_LIGHT_TONES

        scheme = {
            # Primary colors
            'primary': self.primary_palette.get_hex(tones['primary']),
            'on_primary': self.primary_palette.get_hex(tones['on_primary']),
            'primary_container': self.primary_palette.get_hex(tones['primary_container']),
            'on_primary_container': self.primary_palette.get_hex(tones['on_primary_container']),

            # Surface tint (same as primary, used for M3 elevation tinting)
            'surface_tint': self.primary_palette.get_hex(tones['primary']),

            # Secondary colors
            'secondary': self.secondary_palette.get_hex(tones['secondary']),
            'on_secondary': self.secondary_palette.get_hex(tones['on_secondary']),
            'secondary_container': self.secondary_palette.get_hex(tones['secondary_container']),
            'on_secondary_container': self.secondary_palette.get_hex(tones['on_secondary_container']),

            # Tertiary colors
            'tertiary': self.tertiary_palette.get_hex(tones['tertiary']),
            'on_tertiary': self.tertiary_palette.get_hex(tones['on_tertiary']),
            'tertiary_container': self.tertiary_palette.get_hex(tones['tertiary_container']),
            'on_tertiary_container': self.tertiary_palette.get_hex(tones['on_tertiary_container']),

            # Error colors
            'error': self.error_palette.get_hex(tones['error']),
            'on_error': self.error_palette.get_hex(tones['on_error']),
            'error_container': self.error_palette.get_hex(tones['error_container']),
            'on_error_container': self.error_palette.get_hex(tones['on_error_container']),

            # Surface colors
            'surface': self.neutral_palette.get_hex(tones['surface']),
            'on_surface': self.neutral_palette.get_hex(tones['on_surface']),
            'surface_variant': self.neutral_variant_palette.get_hex(tones['surface_variant']),
            'on_surface_variant': self.neutral_variant_palette.get_hex(tones['on_surface_variant']),

            # Surface containers
            'surface_container_lowest': self.neutral_palette.get_hex(tones['surface_container_lowest']),
            'surface_container_low': self.neutral_palette.get_hex(tones['surface_container_low']),
            'surface_container': self.neutral_palette.get_hex(tones['surface_container']),
            'surface_container_high': self.neutral_palette.get_hex(tones['surface_container_high']),
            'surface_container_highest': self.neutral_palette.get_hex(tones['surface_container_highest']),

            # Outline and other
            'outline': self.neutral_variant_palette.get_hex(tones['outline']),
            'outline_variant': self.neutral_variant_palette.get_hex(tones['outline_variant']),
            'shadow': self.neutral_palette.get_hex(tones['shadow']),
            'scrim': self.neutral_palette.get_hex(tones['scrim']),

            # Inverse colors
            'inverse_surface': self.neutral_palette.get_hex(tones['inverse_surface']),
            'inverse_on_surface': self.neutral_palette.get_hex(tones['inverse_on_surface']),
            'inverse_primary': self.primary_palette.get_hex(tones['inverse_primary']),

            # Background (same as surface in MD3)
            'background': self.neutral_palette.get_hex(tones['surface']),
            'on_background': self.neutral_palette.get_hex(tones['on_surface']),

            # Surface dim and bright
            'surface_dim': self.neutral_palette.get_hex(tones['surface']),
            'surface_bright': self.neutral_palette.get_hex(tones['surface_container_highest'] + 5),

            # Fixed colors
            'primary_fixed': self.primary_palette.get_hex(90),
            'primary_fixed_dim': self.primary_palette.get_hex(80),
            'on_primary_fixed': self.primary_palette.get_hex(10),
            'on_primary_fixed_variant': self.primary_palette.get_hex(30),
            'secondary_fixed': self.secondary_palette.get_hex(90),
            'secondary_fixed_dim': self.secondary_palette.get_hex(80),
            'on_secondary_fixed': self.secondary_palette.get_hex(10),
            'on_secondary_fixed_variant': self.secondary_palette.get_hex(30),
            'tertiary_fixed': self.tertiary_palette.get_hex(90),
            'tertiary_fixed_dim': self.tertiary_palette.get_hex(80),
            'on_tertiary_fixed': self.tertiary_palette.get_hex(10),
            'on_tertiary_fixed_variant': self.tertiary_palette.get_hex(30),
        }

        return scheme


# Backward compatibility alias
MaterialScheme = SchemeContent


# =============================================================================
# Helper Functions
# =============================================================================

def harmonize_color(design_color: Hct, source_color: Hct, amount: float = 0.5) -> Hct:
    """
    Shift a design color's hue towards a source color's hue.

    Used to make custom colors feel more cohesive with the theme.

    Args:
        design_color: The color to adjust
        source_color: The reference color to harmonize towards
        amount: How much to shift (0-1, default 0.5)

    Returns:
        Harmonized HCT color
    """
    diff = _hue_difference(source_color.hue, design_color.hue)
    rotation = min(diff * amount, 15.0)  # Max 15° rotation
    if _shorter_rotation(source_color.hue, design_color.hue) < 0:
        rotation = -rotation
    new_hue = (design_color.hue + rotation) % 360.0
    return Hct(new_hue, design_color.chroma, design_color.tone)


def _hue_difference(hue1: float, hue2: float) -> float:
    """Calculate the absolute difference between two hues."""
    diff = abs(hue1 - hue2)
    return min(diff, 360.0 - diff)


def _shorter_rotation(from_hue: float, to_hue: float) -> float:
    """Calculate the shorter rotation direction between hues."""
    diff = to_hue - from_hue
    if diff > 180.0:
        return diff - 360.0
    elif diff < -180.0:
        return diff + 360.0
    return diff
