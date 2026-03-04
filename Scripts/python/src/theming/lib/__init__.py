"""
Theming library - Color extraction and theme generation.

This package provides:
- HCT color space implementation (CAM16, Hct, TonalPalette)
- Material Design 3 scheme generation
- Color utilities (RGB, HSL conversions)
- Image reading and palette extraction
- Template rendering (Matugen compatible)
"""

from .color import Color, rgb_to_hsl, hsl_to_rgb, adjust_surface
from .hct import Hct, Cam16, TonalPalette, TemperatureCache, fix_if_disliked
from .material import MaterialScheme, SchemeContent, harmonize_color
from .contrast import ensure_contrast, contrast_ratio, is_dark
from .image import read_image, ImageReadError
from .palette import extract_palette
from .quantizer import extract_source_color, source_color_to_rgb
from .theme import generate_theme
from .renderer import TemplateRenderer
from .scheme import expand_predefined_scheme, inject_terminal_colors

__all__ = [
    # Color
    "Color",
    "rgb_to_hsl",
    "hsl_to_rgb",
    "adjust_surface",
    # HCT
    "Hct",
    "Cam16",
    "TonalPalette",
    "TemperatureCache",
    "fix_if_disliked",
    # Material
    "MaterialScheme",
    "SchemeContent",
    "harmonize_color",
    # Contrast
    "ensure_contrast",
    "contrast_ratio",
    "is_dark",
    # Image
    "read_image",
    "ImageReadError",
    # Palette
    "extract_palette",
    # Quantizer (Wu + Score algorithm matching matugen)
    "extract_source_color",
    "source_color_to_rgb",
    # Theme
    "generate_theme",
    # Renderer
    "TemplateRenderer",
    # Scheme
    "expand_predefined_scheme",
    "inject_terminal_colors",
]
