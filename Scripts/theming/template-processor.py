#!/usr/bin/env python3
"""
Themer - Wallpaper-based color extraction and theme generation.

A CLI tool that extracts dominant colors from wallpaper images and generates
Material Design or simpler accent-based color themes with light/dark variants.

Usage:
    python3 template-processor.py IMAGE_PATH [OPTIONS]

Options:
    --material    Generate Material-style colors (default)
    --normal      Generate simpler accent-based palette
    --dark        Generate dark theme only
    --light       Generate light theme only
    --both        Generate both themes (default)
    --output FILE Write JSON to file (stdout if omitted)

Example:
    python3 template-processor.py ~/wallpaper.png --material --both
    python3 template-processor.py ~/wallpaper.jpg --dark -o theme.json

Author: Noctalia Team
License: MIT
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import zlib
try:
    import tomllib
except ImportError:
    # Fallback to tomli if available (for older python), or error
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None

from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Any

# =============================================================================
# Type Definitions
# =============================================================================

RGB = tuple[int, int, int]
HSL = tuple[float, float, float]
ThemeMode = Literal["dark", "light"]


@dataclass
class Color:
    """Represents a color with RGB values (0-255)."""
    r: int
    g: int
    b: int
    
    @classmethod
    def from_rgb(cls, rgb: RGB) -> Color:
        return cls(rgb[0], rgb[1], rgb[2])
    
    @classmethod
    def from_hex(cls, hex_str: str) -> Color:
        """Parse hex color string (#RRGGBB or RRGGBB)."""
        hex_str = hex_str.lstrip('#')
        return cls(
            int(hex_str[0:2], 16),
            int(hex_str[2:4], 16),
            int(hex_str[4:6], 16)
        )
    
    def to_rgb(self) -> RGB:
        return (self.r, self.g, self.b)
    
    def to_hex(self) -> str:
        """Convert to hex string (#RRGGBB)."""
        return f"#{self.r:02x}{self.g:02x}{self.b:02x}"
    
    def to_hsl(self) -> HSL:
        """Convert RGB to HSL."""
        return rgb_to_hsl(self.r, self.g, self.b)
    
    @classmethod
    def from_hsl(cls, h: float, s: float, l: float) -> Color:
        """Create Color from HSL values."""
        r, g, b = hsl_to_rgb(h, s, l)
        return cls(r, g, b)


# =============================================================================
# Color Utilities (RGB/HSL Conversion)
# =============================================================================

def rgb_to_hsl(r: int, g: int, b: int) -> HSL:
    """
    Convert RGB (0-255) to HSL (0-360, 0-1, 0-1).
    
    Args:
        r: Red component (0-255)
        g: Green component (0-255)
        b: Blue component (0-255)
    
    Returns:
        Tuple of (hue, saturation, lightness)
    """
    r_norm = r / 255.0
    g_norm = g / 255.0
    b_norm = b / 255.0
    
    max_c = max(r_norm, g_norm, b_norm)
    min_c = min(r_norm, g_norm, b_norm)
    delta = max_c - min_c
    
    # Lightness
    l = (max_c + min_c) / 2.0
    
    if delta == 0:
        h = 0.0
        s = 0.0
    else:
        # Saturation
        s = delta / (1 - abs(2 * l - 1)) if l != 0 and l != 1 else 0
        
        # Hue
        if max_c == r_norm:
            h = 60.0 * (((g_norm - b_norm) / delta) % 6)
        elif max_c == g_norm:
            h = 60.0 * (((b_norm - r_norm) / delta) + 2)
        else:
            h = 60.0 * (((r_norm - g_norm) / delta) + 4)
    
    return (h, s, l)


def hsl_to_rgb(h: float, s: float, l: float) -> RGB:
    """
    Convert HSL (0-360, 0-1, 0-1) to RGB (0-255).
    
    Args:
        h: Hue (0-360)
        s: Saturation (0-1)
        l: Lightness (0-1)
    
    Returns:
        Tuple of (r, g, b)
    """
    if s == 0:
        # Achromatic (gray)
        v = int(round(l * 255))
        return (v, v, v)
    
    def hue_to_rgb(p: float, q: float, t: float) -> float:
        if t < 0:
            t += 1
        if t > 1:
            t -= 1
        if t < 1/6:
            return p + (q - p) * 6 * t
        if t < 1/2:
            return q
        if t < 2/3:
            return p + (q - p) * (2/3 - t) * 6
        return p
    
    q = l * (1 + s) if l < 0.5 else l + s - l * s
    p = 2 * l - q
    h_norm = h / 360.0
    
    r = hue_to_rgb(p, q, h_norm + 1/3)
    g = hue_to_rgb(p, q, h_norm)
    b = hue_to_rgb(p, q, h_norm - 1/3)
    
    return (
        int(round(r * 255)),
        int(round(g * 255)),
        int(round(b * 255))
    )


def adjust_lightness(color: Color, target_l: float) -> Color:
    """Adjust a color's lightness to a target value (0-1)."""
    h, s, _ = color.to_hsl()
    return Color.from_hsl(h, s, target_l)


def shift_hue(color: Color, degrees: float) -> Color:
    """Shift a color's hue by specified degrees."""
    h, s, l = color.to_hsl()
    new_h = (h + degrees) % 360
    return Color.from_hsl(new_h, s, l)


def _adjust_surface(color: Color, s_max: float, l_target: float) -> Color:
    """Derive a surface color from a base color with saturation limit and target lightness."""
    h, s, _ = color.to_hsl()
    return Color.from_hsl(h, min(s, s_max), l_target)



def saturate(color: Color, amount: float) -> Color:
    """Adjust saturation by amount (-1 to 1)."""
    h, s, l = color.to_hsl()
    new_s = max(0.0, min(1.0, s + amount))
    return Color.from_hsl(h, new_s, l)


# =============================================================================
# Contrast Utilities (WCAG Luminance/Contrast)
# =============================================================================

def relative_luminance(r: int, g: int, b: int) -> float:
    """
    Calculate relative luminance per WCAG 2.1.
    
    The formula converts sRGB to linear RGB, then applies the luminance formula:
    L = 0.2126 * R + 0.7152 * G + 0.0722 * B
    
    Args:
        r, g, b: RGB components (0-255)
    
    Returns:
        Relative luminance (0-1)
    """
    def linearize(c: int) -> float:
        c_norm = c / 255.0
        if c_norm <= 0.03928:
            return c_norm / 12.92
        return ((c_norm + 0.055) / 1.055) ** 2.4
    
    r_lin = linearize(r)
    g_lin = linearize(g)
    b_lin = linearize(b)
    
    return 0.2126 * r_lin + 0.7152 * g_lin + 0.0722 * b_lin


def contrast_ratio(color1: Color, color2: Color) -> float:
    """
    Calculate WCAG contrast ratio between two colors.
    
    Returns a value between 1:1 (identical) and 21:1 (black/white).
    """
    l1 = relative_luminance(color1.r, color1.g, color1.b)
    l2 = relative_luminance(color2.r, color2.g, color2.b)
    
    lighter = max(l1, l2)
    darker = min(l1, l2)
    
    return (lighter + 0.05) / (darker + 0.05)


def is_dark(color: Color) -> bool:
    """Determine if a color is perceptually dark."""
    return relative_luminance(color.r, color.g, color.b) < 0.179


def ensure_contrast(
    foreground: Color,
    background: Color,
    min_ratio: float = 4.5,
    prefer_light: bool | None = None
) -> Color:
    """
    Adjust foreground color to meet minimum contrast ratio against background.
    
    Args:
        foreground: The color to adjust
        background: The background color (not modified)
        min_ratio: Minimum contrast ratio (default 4.5 for WCAG AA)
        prefer_light: If True, prefer lightening; if False, prefer darkening;
                     if None, auto-detect based on background
    
    Returns:
        Adjusted foreground color meeting contrast requirements
    """
    current_ratio = contrast_ratio(foreground, background)
    if current_ratio >= min_ratio:
        return foreground
    
    h, s, l = foreground.to_hsl()
    bg_dark = is_dark(background)
    
    # Determine direction to adjust
    if prefer_light is None:
        prefer_light = bg_dark
    
    # Binary search for the right lightness
    if prefer_light:
        low, high = l, 1.0
    else:
        low, high = 0.0, l
    
    best_color = foreground
    for _ in range(20):  # Max iterations
        mid = (low + high) / 2
        test_color = Color.from_hsl(h, s, mid)
        ratio = contrast_ratio(test_color, background)
        
        if ratio >= min_ratio:
            best_color = test_color
            if prefer_light:
                high = mid
            else:
                low = mid
        else:
            if prefer_light:
                low = mid
            else:
                high = mid
    
    return best_color

# Alias for consistent naming
_ensure_contrast = ensure_contrast



def get_contrasting_color(background: Color, min_ratio: float = 4.5) -> Color:
    """Get a contrasting foreground color (black or white variant)."""
    if is_dark(background):
        # Light foreground for dark background
        fg = Color(243, 237, 247)  # Off-white
    else:
        # Dark foreground for light background
        fg = Color(14, 14, 67)  # Dark blue-black
    
    return ensure_contrast(fg, background, min_ratio)


# =============================================================================
# Image Reader (PNG/JPEG Parsing)
# =============================================================================

class ImageReadError(Exception):
    """Raised when image cannot be read or parsed."""
    pass


def read_png(path: Path) -> list[RGB]:
    """
    Parse a PNG file and extract RGB pixels.
    
    Supports 8-bit RGB and RGBA color types (most common for wallpapers).
    Uses zlib for IDAT decompression and handles PNG filters.
    """
    with open(path, 'rb') as f:
        data = f.read()
    
    # Verify PNG signature
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ImageReadError("Invalid PNG signature")
    
    pos = 8
    width = 0
    height = 0
    bit_depth = 0
    color_type = 0
    idat_chunks: list[bytes] = []
    
    while pos < len(data):
        # Read chunk length and type
        chunk_len = struct.unpack('>I', data[pos:pos+4])[0]
        chunk_type = data[pos+4:pos+8]
        chunk_data = data[pos+8:pos+8+chunk_len]
        pos += 12 + chunk_len  # length + type + data + crc
        
        if chunk_type == b'IHDR':
            width = struct.unpack('>I', chunk_data[0:4])[0]
            height = struct.unpack('>I', chunk_data[4:8])[0]
            bit_depth = chunk_data[8]
            color_type = chunk_data[9]
            
            if bit_depth != 8:
                raise ImageReadError(f"Unsupported bit depth: {bit_depth}")
            if color_type not in (2, 6):  # RGB or RGBA
                raise ImageReadError(f"Unsupported color type: {color_type}")
        
        elif chunk_type == b'IDAT':
            idat_chunks.append(chunk_data)
        
        elif chunk_type == b'IEND':
            break
    
    if not idat_chunks or width == 0:
        raise ImageReadError("Missing image data")
    
    # Decompress all IDAT chunks
    compressed = b''.join(idat_chunks)
    raw_data = zlib.decompress(compressed)
    
    # Calculate bytes per pixel and row
    bpp = 3 if color_type == 2 else 4  # RGB or RGBA
    stride = width * bpp + 1  # +1 for filter byte
    
    pixels: list[RGB] = []
    prev_row: list[int] = [0] * (width * bpp)
    
    for y in range(height):
        row_start = y * stride
        filter_type = raw_data[row_start]
        row_data = list(raw_data[row_start + 1:row_start + stride])
        
        # Apply PNG filter reconstruction
        unfiltered = _png_unfilter(row_data, prev_row, bpp, filter_type)
        prev_row = unfiltered
        
        # Extract RGB values (skip alpha if present)
        for x in range(width):
            idx = x * bpp
            r, g, b = unfiltered[idx], unfiltered[idx+1], unfiltered[idx+2]
            pixels.append((r, g, b))
    
    return pixels


def _png_unfilter(
    row: list[int],
    prev_row: list[int],
    bpp: int,
    filter_type: int
) -> list[int]:
    """Apply PNG filter reconstruction."""
    result = [0] * len(row)
    
    for i in range(len(row)):
        x = row[i]
        a = result[i - bpp] if i >= bpp else 0
        b = prev_row[i]
        c = prev_row[i - bpp] if i >= bpp else 0
        
        if filter_type == 0:  # None
            result[i] = x
        elif filter_type == 1:  # Sub
            result[i] = (x + a) & 0xFF
        elif filter_type == 2:  # Up
            result[i] = (x + b) & 0xFF
        elif filter_type == 3:  # Average
            result[i] = (x + (a + b) // 2) & 0xFF
        elif filter_type == 4:  # Paeth
            result[i] = (x + _paeth_predictor(a, b, c)) & 0xFF
        else:
            raise ImageReadError(f"Unknown PNG filter type: {filter_type}")
    
    return result


def _paeth_predictor(a: int, b: int, c: int) -> int:
    """Paeth predictor for PNG filter reconstruction."""
    p = a + b - c
    pa = abs(p - a)
    pb = abs(p - b)
    pc = abs(p - c)
    
    if pa <= pb and pa <= pc:
        return a
    elif pb <= pc:
        return b
    return c


def read_jpeg(path: Path) -> list[RGB]:
    """
    Parse a JPEG file and extract RGB pixels.
    
    Supports baseline (SOF0), extended (SOF1), and progressive (SOF2) JPEG.
    This is a simplified decoder that extracts dimensions then samples colors.
    """
    with open(path, 'rb') as f:
        data = f.read()
    
    # Verify JPEG signature (SOI marker)
    if data[:2] != b'\xff\xd8':
        raise ImageReadError("Invalid JPEG signature")
    
    pos = 2
    width = 0
    height = 0
    
    # SOF markers that contain image dimensions
    # SOF0=Baseline, SOF1=Extended, SOF2=Progressive, SOF3=Lossless
    # SOF5-7=Differential variants, SOF9-11=Arithmetic coding variants
    sof_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                   0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    
    # Standalone markers (no length field)
    standalone_markers = {0xD0, 0xD1, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7,  # RST0-7
                          0xD8,  # SOI
                          0xD9,  # EOI
                          0x01}  # TEM
    
    while pos < len(data) - 1:
        # Find next marker
        if data[pos] != 0xFF:
            pos += 1
            continue
        
        # Skip padding 0xFF bytes
        while pos < len(data) and data[pos] == 0xFF:
            pos += 1
        
        if pos >= len(data):
            break
        
        marker = data[pos]
        pos += 1
        
        # Check for SOF marker (contains dimensions)
        if marker in sof_markers:
            if pos + 7 <= len(data):
                # Skip segment length (2 bytes), precision (1 byte)
                height = struct.unpack('>H', data[pos+3:pos+5])[0]
                width = struct.unpack('>H', data[pos+5:pos+7])[0]
                break
        
        # End of image
        if marker == 0xD9:
            break
        
        # Skip segment data for markers with length field
        if marker not in standalone_markers and marker != 0x00:
            if pos + 2 <= len(data):
                seg_len = struct.unpack('>H', data[pos:pos+2])[0]
                pos += seg_len
    
    if width == 0 or height == 0:
        raise ImageReadError("Could not parse JPEG dimensions")
    
    # Since full JPEG decoding is extremely complex without external libraries,
    # we fall back to sampling the raw data for color approximation.
    return _sample_jpeg_colors(data, width, height)


def _read_image_imagemagick(path: Path) -> list[RGB]:
    """
    Read image using ImageMagick's convert command.
    
    Converts image to PPM format (trivial to parse) and extracts RGB pixels.
    This method works accurately for any image format ImageMagick supports.
    """
    import subprocess
    
    # Use magick or convert command
    # -depth 8: 8 bits per channel
    # -resize: downsample for performance (we don't need full resolution for color extraction)
    # ppm: output as PPM format (easy to parse)
    
    # Downsample to max 200x200 for performance
    resize_spec = "200x200>"
    
    try:
        # Try 'magick convert' first (ImageMagick 7+), fallback to 'convert' (ImageMagick 6)
        try:
            result = subprocess.run(
                ['magick', 'convert', str(path), '-resize', resize_spec, '-depth', '8', 'ppm:-'],
                capture_output=True,
                check=True
            )
        except FileNotFoundError:
            result = subprocess.run(
                ['convert', str(path), '-resize', resize_spec, '-depth', '8', 'ppm:-'],
                capture_output=True,
                check=True
            )
    except subprocess.CalledProcessError as e:
        raise ImageReadError(f"ImageMagick failed: {e.stderr.decode()}")
    except FileNotFoundError:
        raise ImageReadError("ImageMagick not found. Please install imagemagick.")
    
    ppm_data = result.stdout
    return _parse_ppm(ppm_data)


def _parse_ppm(data: bytes) -> list[RGB]:
    """
    Parse PPM (Portable Pixmap) binary format.
    
    PPM P6 format:
    P6
    width height
    maxval
    <binary RGB data>
    """
    pos = 0
    tokens: list[str] = []
    
    # Read header tokens (need 4: P6, width, height, maxval)
    while len(tokens) < 4 and pos < len(data):
        # Skip whitespace
        while pos < len(data) and data[pos:pos+1] in (b' ', b'\t', b'\n', b'\r'):
            pos += 1
        
        # Skip comments
        if pos < len(data) and data[pos:pos+1] == b'#':
            while pos < len(data) and data[pos:pos+1] != b'\n':
                pos += 1
            continue
        
        # Read token
        token_start = pos
        while pos < len(data) and data[pos:pos+1] not in (b' ', b'\t', b'\n', b'\r', b'#'):
            pos += 1
        
        if pos > token_start:
            tokens.append(data[token_start:pos].decode('ascii'))
    
    if len(tokens) < 4 or tokens[0] != 'P6':
        raise ImageReadError(f"Invalid PPM format: {tokens}")
    
    width = int(tokens[1])
    height = int(tokens[2])
    maxval = int(tokens[3])
    
    # Skip exactly one whitespace character after maxval (per PPM spec)
    if pos < len(data) and data[pos:pos+1] in (b' ', b'\t', b'\n', b'\r'):
        pos += 1
    
    pixel_data = data[pos:]
    
    # Parse RGB triplets
    pixels: list[RGB] = []
    scale = 255.0 / maxval if maxval != 255 else 1.0
    
    for i in range(0, min(len(pixel_data), width * height * 3), 3):
        if i + 2 < len(pixel_data):
            r = int(pixel_data[i] * scale)
            g = int(pixel_data[i + 1] * scale)
            b = int(pixel_data[i + 2] * scale)
            pixels.append((r, g, b))
    
    if not pixels:
        raise ImageReadError("No pixels extracted from PPM data")
    
    return pixels


def read_image(path: Path) -> list[RGB]:
    """
    Read an image file and return its pixels as RGB tuples.
    
    Uses ImageMagick for accurate color extraction from any format.
    Falls back to native PNG parsing if ImageMagick is unavailable.
    """
    suffix = path.suffix.lower()
    
    # Try ImageMagick first (works for any format)
    try:
        return _read_image_imagemagick(path)
    except ImageReadError:
        # Fall back to native parsing for PNG
        if suffix == '.png':
            return read_png(path)
        raise


# =============================================================================
# Palette Extraction (K-means Clustering)
# =============================================================================

def downsample_pixels(pixels: list[RGB], factor: int = 4) -> list[RGB]:
    """
    Downsample pixels for faster processing.
    
    Takes every Nth pixel to reduce dataset size while maintaining
    color distribution characteristics.
    """
    if factor <= 1:
        return pixels
    
    # Calculate step based on factor squared (for 2D image)
    step = factor * factor
    return pixels[::step]


def color_distance_hsl(c1: HSL, c2: HSL) -> float:
    """
    Calculate perceptual distance between two colors in HSL space.
    
    Hue is weighted less for low-saturation colors (grays).
    """
    h1, s1, l1 = c1
    h2, s2, l2 = c2
    
    # Hue distance (circular)
    dh = min(abs(h1 - h2), 360 - abs(h1 - h2)) / 180.0
    
    # Weight hue by average saturation (grays have similar hues but shouldn't match)
    avg_sat = (s1 + s2) / 2
    dh_weighted = dh * avg_sat
    
    ds = abs(s1 - s2)
    dl = abs(l1 - l2)
    
    return (dh_weighted ** 2 + ds ** 2 + dl ** 2) ** 0.5


def kmeans_cluster(
    colors: list[RGB],
    k: int = 5,
    iterations: int = 15
) -> list[tuple[RGB, int]]:
    """
    Perform K-means clustering on colors.
    
    Returns list of (centroid_rgb, cluster_size) tuples, sorted by cluster size.
    Uses deterministic initialization for reproducible results.
    """
    if len(colors) < k:
        # Not enough colors, return what we have
        unique = list(set(colors))
        return [(c, colors.count(c)) for c in unique[:k]]
    
    # Convert to HSL for perceptual clustering
    colors_hsl = [rgb_to_hsl(*c) for c in colors]
    
    # Deterministic initialization: pick evenly spaced colors from sorted list
    sorted_indices = sorted(range(len(colors_hsl)), key=lambda i: colors_hsl[i])
    step = len(sorted_indices) // k
    centroids = [colors_hsl[sorted_indices[i * step]] for i in range(k)]
    
    # K-means iterations
    for _ in range(iterations):
        # Assign colors to nearest centroid
        clusters: list[list[HSL]] = [[] for _ in range(k)]
        
        for color in colors_hsl:
            min_dist = float('inf')
            min_idx = 0
            for i, centroid in enumerate(centroids):
                dist = color_distance_hsl(color, centroid)
                if dist < min_dist:
                    min_dist = dist
                    min_idx = i
            clusters[min_idx].append(color)
        
        # Update centroids
        new_centroids = []
        for i, cluster in enumerate(clusters):
            if cluster:
                avg_h = sum(c[0] for c in cluster) / len(cluster)
                avg_s = sum(c[1] for c in cluster) / len(cluster)
                avg_l = sum(c[2] for c in cluster) / len(cluster)
                new_centroids.append((avg_h, avg_s, avg_l))
            else:
                new_centroids.append(centroids[i])
        
        centroids = new_centroids
    
    # Final assignment and counting
    cluster_counts = [0] * k
    for color in colors_hsl:
        min_dist = float('inf')
        min_idx = 0
        for i, centroid in enumerate(centroids):
            dist = color_distance_hsl(color, centroid)
            if dist < min_dist:
                min_dist = dist
                min_idx = i
        cluster_counts[min_idx] += 1
    
    # Convert centroids back to RGB and pair with counts
    results = []
    for i, centroid in enumerate(centroids):
        rgb = hsl_to_rgb(*centroid)
        results.append((rgb, cluster_counts[i]))
    
    # Sort by cluster size (most common first)
    results.sort(key=lambda x: -x[1])
    
    return results


def extract_palette(pixels: list[RGB], k: int = 5) -> list[Color]:
    """
    Extract K dominant colors from pixel data.
    
    Args:
        pixels: List of RGB tuples
        k: Number of colors to extract
    
    Returns:
        List of Color objects, sorted by dominance
    """
    # Downsample for performance
    sampled = downsample_pixels(pixels, factor=4)
    
    # Filter out very dark, very bright, and desaturated pixels
    # This ensures we get vibrant, usable theme colors
    filtered = []
    for p in sampled:
        h, s, l = rgb_to_hsl(*p)
        # Keep colors that are:
        # - Not too dark (L > 0.15)
        # - Not too bright (L < 0.85)
        # - Reasonably saturated (S > 0.15)
        if 0.15 < l < 0.85 and s > 0.15:
            filtered.append(p)
    
    # Fall back to all pixels if filtering removed too many
    if len(filtered) < k * 10:
        # Try a less strict filter
        filtered = []
        for p in sampled:
            lum = relative_luminance(*p)
            if 0.05 < lum < 0.95:
                filtered.append(p)
    
    if len(filtered) < k * 10:
        filtered = sampled
    
    # Cluster
    clusters = kmeans_cluster(filtered, k=k)
    
    # Post-filter: remove very dark colors from results
    result_colors = []
    for rgb, count in clusters:
        color = Color.from_rgb(rgb)
        h, s, l = color.to_hsl()
        # Skip very dark colors (they'll be used for surfaces anyway)
        if l > 0.20 or len(result_colors) == 0:
            result_colors.append(color)
    
    # Ensure we have enough colors by deriving from primary
    while len(result_colors) < k:
        primary = result_colors[0]
        offset = len(result_colors) * 30
        result_colors.append(shift_hue(primary, offset))
    
    return result_colors[:k]


def find_error_color(palette: list[Color]) -> Color:
    """
    Find or generate an error color (red-biased).
    
    Looks for existing red in palette, otherwise returns a default.
    """
    # Look for a red-ish color in the palette
    for color in palette:
        h, s, l = color.to_hsl()
        # Red hues: 0-30 or 330-360
        if (h <= 30 or h >= 330) and s > 0.4 and 0.3 < l < 0.7:
            return color
    
    # Default error red
    return Color.from_hex("#FD4663")


def derive_harmonious_colors(primary: Color) -> tuple[Color, Color, Color]:
    """
    Derive secondary and tertiary colors as harmonious complements to primary.
    
    Uses color theory:
    - Secondary: Analogous (30° hue shift) - similar but distinct
    - Tertiary: Split-complementary (150° hue shift) - contrasting but harmonious
    - Quaternary: Complementary (180° hue shift) - for accents
    
    Returns:
        Tuple of (secondary, tertiary, quaternary) colors
    """
    h, s, l = primary.to_hsl()
    
    # Secondary: analogous - similar warmth/coolness, shifted hue
    secondary = Color.from_hsl((h + 30) % 360, s, l)
    
    # Tertiary: split-complementary - provides contrast while staying harmonious
    tertiary = Color.from_hsl((h + 150) % 360, s, l)
    
    # Quaternary: complementary - opposite on color wheel
    quaternary = Color.from_hsl((h + 180) % 360, s, l)
    
    return secondary, tertiary, quaternary


# =============================================================================
# Theme Generation (Material/Normal)
# =============================================================================


def generate_material_dark(palette: list[Color]) -> dict[str, str]:
    """
    Generate Material Design dark theme from palette.
    
    Dark theme characteristics:
    - Dark surfaces (low luminance backgrounds)
    - Bright, slightly desaturated accent colors
    - High contrast text
    - Secondary/tertiary derived as harmonious colors from primary
    """
    primary = palette[0] if palette else Color(255, 245, 155)
    # Derive harmonious colors from primary
    secondary, tertiary, quaternary = derive_harmonious_colors(primary)
    error = find_error_color(palette)
    
    # Adjust colors for dark theme
    # Primary should be bright enough to stand out on dark surface
    h, s, _ = primary.to_hsl()
    primary_adjusted = Color.from_hsl(h, min(s, 0.7), 0.75)
    
    h, s, _ = secondary.to_hsl()
    secondary_adjusted = Color.from_hsl(h, min(s, 0.6), 0.70)
    
    h, s, _ = tertiary.to_hsl()
    tertiary_adjusted = Color.from_hsl(h, min(s, 0.6), 0.75)
    
    # Surface colors (very dark, slightly tinted with primary hue)
    surface_h, _, _ = primary.to_hsl()
    surface = Color.from_hsl(surface_h, 0.6, 0.05)
    surface_variant = Color.from_hsl(surface_h, 0.5, 0.10)
    
    base_primary = primary # Use primary for hue base
    mSurface = _adjust_surface(base_primary, 0.6, 0.05)
    mSurfaceVariant = _adjust_surface(base_primary, 0.45, 0.14)   # Slightly lighter/diff saturation

    # Foreground colors - Ensure they are readable but not too saturated (avoid yellow text)
    # Use primary hue but low saturation (0.05) for text
    text_h, _, _ = base_primary.to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.95)
    mOnSurface = _ensure_contrast(base_on_surface, mSurface, 4.5)
    
    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.80)
    mOnSurfaceVariant = _ensure_contrast(base_on_surface_variant, mSurfaceVariant, 4.5)

    mOutline = _adjust_surface(base_primary, 0.30, 0.40)
    
    # Dark foreground for bright backgrounds
    dark_fg = Color.from_hsl(base_primary.to_hsl()[0], 0.7, 0.10)
    
    # Ensure contrast
    on_primary = _ensure_contrast(dark_fg, primary_adjusted, 4.5)
    on_secondary = _ensure_contrast(dark_fg, secondary_adjusted, 4.5)
    on_tertiary = _ensure_contrast(dark_fg, tertiary_adjusted, 4.5)
    on_error = _ensure_contrast(dark_fg, error, 4.5)
    
    # Outline and shadow
    shadow = mSurface
    
    return {
        "mPrimary": primary_adjusted.to_hex(),
        "mOnPrimary": on_primary.to_hex(),
        "mSecondary": secondary_adjusted.to_hex(),
        "mOnSecondary": on_secondary.to_hex(),
        "mTertiary": tertiary_adjusted.to_hex(),
        "mOnTertiary": on_tertiary.to_hex(),
        "mError": error.to_hex(),
        "mOnError": on_error.to_hex(),
        "mSurface": mSurface.to_hex(),
        "mOnSurface": mOnSurface.to_hex(),
        "mSurfaceVariant": mSurfaceVariant.to_hex(),
        "mOnSurfaceVariant": mOnSurfaceVariant.to_hex(),
        "mOutline": mOutline.to_hex(),
        "mShadow": shadow.to_hex(),
    }


def generate_material_light(palette: list[Color]) -> dict[str, str]:
    """
    Generate Material Design light theme from palette.
    
    Light theme characteristics:
    - Light surfaces (high luminance backgrounds)
    - Darker, more saturated accent colors
    - Dark text for readability
    """
    primary = palette[0] if palette else Color(93, 101, 245)
    secondary = palette[1] if len(palette) > 1 else shift_hue(primary, 30)
    tertiary = palette[2] if len(palette) > 2 else shift_hue(primary, 180)
    error = find_error_color(palette)
    
    # Adjust colors for light theme
    # Primary should be darker to stand out on light surface
    h, s, _ = primary.to_hsl()
    primary_adjusted = Color.from_hsl(h, min(s + 0.1, 0.8), 0.50)
    
    h, s, _ = secondary.to_hsl()
    secondary_adjusted = Color.from_hsl(h, min(s, 0.5), 0.55)
    
    h, s, _ = tertiary.to_hsl()
    tertiary_adjusted = Color.from_hsl(h, 0.8, 0.15)
    
    # Surface colors (very light, slightly tinted with primary hue)
    base_primary = primary
    mSurface = _adjust_surface(base_primary, 0.4, 0.94)
    mSurfaceVariant = _adjust_surface(base_primary, 0.5, 0.97)
    
    # Foreground colors - Ensure they are readable but not too saturated (avoid yellow text)
    # Use primary hue but low saturation (0.05) for text
    text_h, _, _ = base_primary.to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.10)
    mOnSurface = _ensure_contrast(base_on_surface, mSurface, 4.5)
    
    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.45)
    mOnSurfaceVariant = _ensure_contrast(base_on_surface_variant, mSurfaceVariant, 4.5)
    
    # Light foreground for dark backgrounds
    light_fg = Color.from_hsl(base_primary.to_hsl()[0], 0.2, 0.90)
    
    # Ensure contrast
    on_primary = _ensure_contrast(light_fg, primary_adjusted, 4.5)
    on_secondary = _ensure_contrast(light_fg, secondary_adjusted, 4.5)
    on_tertiary = _ensure_contrast(Color(254, 242, 154), tertiary_adjusted, 4.5)
    on_error = _ensure_contrast(Color(14, 14, 67), error, 4.5)
    
    # Outline and shadow
    mOutline = _adjust_surface(base_primary, 0.5, 0.60)
    shadow = Color(243, 237, 247)
    
    return {
        "mPrimary": primary_adjusted.to_hex(),
        "mOnPrimary": on_primary.to_hex(),
        "mSecondary": secondary_adjusted.to_hex(),
        "mOnSecondary": on_secondary.to_hex(),
        "mTertiary": tertiary_adjusted.to_hex(),
        "mOnTertiary": on_tertiary.to_hex(),
        "mError": error.to_hex(),
        "mOnError": on_error.to_hex(),
        "mSurface": mSurface.to_hex(),
        "mOnSurface": mOnSurface.to_hex(),
        "mSurfaceVariant": mSurfaceVariant.to_hex(),
        "mOnSurfaceVariant": mOnSurfaceVariant.to_hex(),
        "mOutline": mOutline.to_hex(),
        "mShadow": shadow.to_hex(),
    }


def generate_normal_dark(palette: list[Color]) -> dict[str, str]:
    """
    Generate wallust-style dark theme from palette.
    
    More vibrant than Material - uses palette colors directly and keeps
    surfaces saturated with the primary hue. Outputs same keys as Material.
    """
    # Use extracted colors directly (wallust style)
    primary = palette[0] if palette else Color(255, 245, 155)
    secondary = palette[1] if len(palette) > 1 else shift_hue(primary, 30)
    tertiary = palette[2] if len(palette) > 2 else shift_hue(primary, 60)
    quaternary = palette[3] if len(palette) > 3 else shift_hue(primary, 180)
    error = find_error_color(palette)
    
    # Keep colors vibrant - preserve saturation
    h, s, l = primary.to_hsl()
    primary_adjusted = Color.from_hsl(h, max(s, 0.7), max(l, 0.65))
    
    h, s, l = secondary.to_hsl()
    secondary_adjusted = Color.from_hsl(h, max(s, 0.6), max(l, 0.60))
    
    h, s, l = tertiary.to_hsl()
    tertiary_adjusted = Color.from_hsl(h, max(s, 0.5), max(l, 0.60))
    
    # Surface: COLORFUL dark - a deep, saturated version of primary
    # Heuristic: Shift Cyan (160-200) slightly towards Blue (+10) to avoid "Teal" look
    surface_hue, s, _ = palette[0].to_hsl()
    if 160 <= surface_hue <= 200:
        surface_hue = (surface_hue + 10) % 360
    
    base_surface = Color.from_hsl(surface_hue, s, 0.5) # l doesn't matter for next step
    
    # Preserving saturation (up to 0.9) to be true to primary color
    mSurface = _adjust_surface(base_surface, 0.90, 0.12)
    mSurfaceVariant = _adjust_surface(base_surface, 0.80, 0.16)
    
    # Text colors - desaturated
    text_h, _, _ = palette[0].to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.95)
    mOnSurface = _ensure_contrast(base_on_surface, mSurface, 4.5)
    
    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.80)
    mOnSurfaceVariant = _ensure_contrast(base_on_surface_variant, mSurfaceVariant, 4.5)
    
    mOutline = _adjust_surface(palette[0], 0.10, 0.30)
    
    # Contrasting foregrounds for accent colors
    dark_fg = Color.from_hsl(palette[0].to_hsl()[0], 0.3, 0.08)
    on_primary = _ensure_contrast(dark_fg, primary_adjusted, 4.5)
    on_secondary = _ensure_contrast(dark_fg, secondary_adjusted, 4.5)
    on_tertiary = _ensure_contrast(dark_fg, tertiary_adjusted, 4.5)
    on_error = _ensure_contrast(dark_fg, error, 4.5)
    
    # Outline uses primary hue, more saturated
    shadow = mSurface
    
    return {
        "mPrimary": primary_adjusted.to_hex(),
        "mOnPrimary": on_primary.to_hex(),
        "mSecondary": secondary_adjusted.to_hex(),
        "mOnSecondary": on_secondary.to_hex(),
        "mTertiary": tertiary_adjusted.to_hex(),
        "mOnTertiary": on_tertiary.to_hex(),
        "mError": error.to_hex(),
        "mOnError": on_error.to_hex(),
        "mSurface": mSurface.to_hex(),
        "mOnSurface": mOnSurface.to_hex(),
        "mSurfaceVariant": mSurfaceVariant.to_hex(),
        "mOnSurfaceVariant": mOnSurfaceVariant.to_hex(),
        "mOutline": mOutline.to_hex(),
        "mShadow": shadow.to_hex(),
    }


def generate_normal_light(palette: list[Color]) -> dict[str, str]:
    """
    Generate wallust-style light theme from palette.
    
    More vibrant than Material - uses palette colors directly and keeps
    surfaces saturated with the primary hue. Outputs same keys as Material.
    """
    # Use extracted colors directly
    primary = palette[0] if palette else Color(93, 101, 245)
    secondary = palette[1] if len(palette) > 1 else shift_hue(primary, 30)
    tertiary = palette[2] if len(palette) > 2 else shift_hue(primary, 60)
    quaternary = palette[3] if len(palette) > 3 else shift_hue(primary, 180)
    error = find_error_color(palette)
    
    # Keep colors vibrant - darken for visibility on light bg
    h, s, l = primary.to_hsl()
    primary_adjusted = Color.from_hsl(h, max(s, 0.7), min(l, 0.45))
    
    h, s, l = secondary.to_hsl()
    secondary_adjusted = Color.from_hsl(h, max(s, 0.6), min(l, 0.40))
    
    h, s, l = tertiary.to_hsl()
    tertiary_adjusted = Color.from_hsl(h, max(s, 0.5), min(l, 0.35))
    
    # Surface: COLORFUL light - a pastel, saturated version of primary
    # Preserving saturation (up to 0.9) to be true to primary color
    mSurface = _adjust_surface(palette[0], 0.90, 0.90)
    mSurfaceVariant = _adjust_surface(palette[0], 0.80, 0.85)
    
    # Foreground colors - tinted with primary hue
    text_h, _, _ = palette[0].to_hsl()
    base_on_surface = Color.from_hsl(text_h, 0.05, 0.10)
    mOnSurface = _ensure_contrast(base_on_surface, mSurface, 4.5)
    
    base_on_surface_variant = Color.from_hsl(text_h, 0.05, 0.35)
    mOnSurfaceVariant = _ensure_contrast(base_on_surface_variant, mSurfaceVariant, 4.5)
    
    # Contrasting foregrounds
    light_fg = Color.from_hsl(text_h, 0.1, 0.95)
    on_primary = ensure_contrast(light_fg, primary_adjusted, 4.5)
    on_secondary = ensure_contrast(light_fg, secondary_adjusted, 4.5)
    on_tertiary = ensure_contrast(light_fg, tertiary_adjusted, 4.5)
    on_error = ensure_contrast(light_fg, error, 4.5)
    
    # Outline uses primary hue, more saturated
    surface_h, surface_s, _ = palette[0].to_hsl()
    mOutline = Color.from_hsl(surface_h, max(surface_s * 0.4, 0.25), 0.65)
    shadow = Color.from_hsl(surface_h, max(surface_s * 0.3, 0.15), 0.80)
    
    return {
        "mPrimary": primary_adjusted.to_hex(),
        "mOnPrimary": on_primary.to_hex(),
        "mSecondary": secondary_adjusted.to_hex(),
        "mOnSecondary": on_secondary.to_hex(),
        "mTertiary": tertiary_adjusted.to_hex(),
        "mOnTertiary": on_tertiary.to_hex(),
        "mError": error.to_hex(),
        "mOnError": on_error.to_hex(),
        "mSurface": mSurface.to_hex(),
        "mOnSurface": mOnSurface.to_hex(),
        "mSurfaceVariant": mSurfaceVariant.to_hex(),
        "mOnSurfaceVariant": mOnSurfaceVariant.to_hex(),
        "mOutline": mOutline.to_hex(),
        "mShadow": shadow.to_hex(),
    }


def generate_theme(
    palette: list[Color],
    mode: ThemeMode,
    material: bool = True
) -> dict[str, str]:
    """Generate theme for specified mode."""
    if material:
        if mode == "dark":
            return generate_material_dark(palette)
        return generate_material_light(palette)
    else:
        if mode == "dark":
            return generate_normal_dark(palette)
        return generate_normal_light(palette)


# =============================================================================
# Template Rendering (Matugen Compatibility)
# =============================================================================

class TemplateRenderer:
    """
    Renders templates using the generated theme colors.
    Compatible with Matugen-style {{colors.name.mode.format}} tags.
    """
    
    # Map from Matugen color names to theme keys
    COLOR_MAP = {
        "primary": "mPrimary",
        "on_primary": "mOnPrimary",
        "primary_container": "mPrimary",         # Mapped to Accent (Bright)
        "on_primary_container": "mOnPrimary",    # Mapped to Text on Accent (Dark)
        "secondary": "mSecondary",
        "on_secondary": "mOnSecondary",
        "secondary_container": "mSecondary",     # Mapped to Accent
        "on_secondary_container": "mOnSecondary",# Mapped to Text on Accent
        "tertiary": "mTertiary",
        "on_tertiary": "mOnTertiary",
        "tertiary_container": "mTertiary",       # Mapped to Accent
        "on_tertiary_container": "mOnTertiary",  # Mapped to Text on Accent
        "error": "mError",
        "on_error": "mOnError",
        "error_container": "mError",              # Fallback
        "on_error_container": "mOnError",         # Fallback
        "surface": "mSurface",
        "on_surface": "mOnSurface",
        "surface_variant": "mSurfaceVariant",
        "on_surface_variant": "mOnSurfaceVariant",
        "outline": "mOutline",
        "outline_variant": "mOutline",
        "shadow": "mShadow",
        "scrim": "mShadow",
        "inverse_surface": "mOnSurface",          # Fallback
        "inverse_on_surface": "mSurface",         # Fallback
        "inverse_primary": "mOnPrimary",          # Fallback
        "background": "mSurface",
        "on_background": "mOnSurface",
        
        # Surface Containers (Material 3)
        "surface_container_lowest": "mSurface",      # Fallback
        "surface_container_low": "mSurface",         # Fallback
        "surface_container": "mSurfaceVariant",      # Fallback
        "surface_container_high": "mSurfaceVariant", # Fallback
        "surface_container_highest": "mSurfaceVariant", # Fallback
        "surface_dim": "mSurface",                   # Fallback
        "surface_bright": "mSurfaceVariant",         # Fallback
        
        # Fixed colors (Material 3)
        "primary_fixed": "mPrimary",             # Fallback
        "primary_fixed_dim": "mPrimary",         # Fallback
        "on_primary_fixed": "mOnPrimary",        # Fallback
        "on_primary_fixed_variant": "mOnPrimary",# Fallback
        "secondary_fixed": "mSecondary",         # Fallback
        "secondary_fixed_dim": "mSecondary",     # Fallback
        "on_secondary_fixed": "mOnSecondary",    # Fallback
        "on_secondary_fixed_variant": "mOnSecondary", # Fallback
        "tertiary_fixed": "mTertiary",           # Fallback
        "tertiary_fixed_dim": "mTertiary",       # Fallback
        "on_tertiary_fixed": "mOnTertiary",      # Fallback
        "on_tertiary_fixed_variant": "mOnTertiary", # Fallback

        # Custom/Noctalia keys
        "hover": "mHover",
        "on_hover": "mOnHover",
    }

    def __init__(self, theme_data: dict[str, dict[str, str]]):
        self.theme_data = theme_data

    def _get_color_value(self, color_name: str, mode: str, format_type: str) -> str:
        """Get processed color value for a template tag."""
        # Map color name to theme key
        key = self.COLOR_MAP.get(color_name)
        if not key:
            return f"{{{{UNKNOWN_COLOR_{color_name}}}}}"

        # Get relevant mode data
        # Handle 'default' mode (active mode if only one generated, or first available)
        if mode == "default":
            mode_data = self.theme_data.get("dark") or self.theme_data.get("light")
        else:
            mode_data = self.theme_data.get(mode)

        if not mode_data:
            return f"{{{{UNKNOWN_MODE_{mode}}}}}"

        hex_color = mode_data.get(key)
        if not hex_color:
             # Fallback to unmapped name (e.g. if input JSON uses standard keys)
             hex_color = mode_data.get(color_name)
        
        if not hex_color:
            return f"{{{{UNKNOWN_KEY_{key}}}}}"

        # Apply format
        if format_type == "hex":
            return hex_color
        elif format_type == "hex_stripped":
            return hex_color.lstrip('#')
        elif format_type == "rgb":
            c = Color.from_hex(hex_color)
            return f"{c.r}, {c.g}, {c.b}"
        elif format_type == "rgba":
            c = Color.from_hex(hex_color)
            return f"{c.r}, {c.g}, {c.b}, 1.0"
        elif format_type in ("hue", "saturation", "lightness"):
            c = Color.from_hex(hex_color)
            h, s, l = c.to_hsl()
            if format_type == "hue": return str(int(h))
            if format_type == "saturation": return str(int(s * 100))
            if format_type == "lightness": return str(int(l * 100))
        
        return hex_color

    def render(self, template_text: str) -> str:
        """Replace all tags in template text."""
        # Generic pattern for {{colors.name.mode.format}}
        pattern = r"\{\{\s*colors\.([a-z_0-9]+)\.([a-z_0-9]+)\.([a-z_0-9]+)\s*\}\}"
        
        def replace(match):
            color_name, mode, format_type = match.groups()
            return self._get_color_value(color_name, mode, format_type)

        return re.sub(pattern, replace, template_text)

    def render_file(self, input_path: Path, output_path: Path):
        """Render a template file to an output path."""
        try:
            template_text = input_path.read_text()
            rendered_text = self.render(template_text)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(rendered_text)
        except Exception as e:
            print(f"Error rendering template {input_path}: {e}", file=sys.stderr)

    def process_config_file(self, config_path: Path):
        """Process Matugen TOML configuration file."""
        if not tomllib:
            print("Error: tomllib module not available (requires Python 3.11+)", file=sys.stderr)
            return

        try:
            with open(config_path, "rb") as f:
                data = tomllib.load(f)
            
            # Matugen config structure: https://github.com/InioX/matugen
            # [config] section (ignored)
            # [templates.name] sections
            
            templates = data.get("templates", {})
            for name, template in templates.items():
                input_path = template.get("input_path")
                output_path = template.get("output_path")
                
                if not input_path or not output_path:
                    continue
                    
                self.render_file(Path(input_path).expanduser(), Path(output_path).expanduser())
                
                # Matugen supports post_hook, we probably can't easily support that blindly
                # without shell=True which is risky, but let's see if we need it.
                # TemplateProcessor.qml puts post_hook in the TOML.
                # We should execute it if possible to fully replicate behavior.
                post_hook = template.get("post_hook")
                if post_hook:
                    import subprocess
                    try:
                        subprocess.run(post_hook, shell=True, check=False)
                    except Exception as e:
                        print(f"Error running post_hook for {name}: {e}", file=sys.stderr)

        except Exception as e:
            print(f"Error processing config file {config_path}: {e}", file=sys.stderr)

def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        prog='themer',
        description='Extract color palettes from wallpapers and generate themes',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 template-processor.py wallpaper.png --material --both
  python3 template-processor.py wallpaper.jpg --dark -o theme.json
  python3 template-processor.py ~/Pictures/bg.png --normal --light
        """
    )
    
    parser.add_argument(
        'image',
        type=Path,
        help='Path to wallpaper image (PNG/JPG)'
    )
    
    # Theme style (mutually exclusive)
    style_group = parser.add_mutually_exclusive_group()
    style_group.add_argument(
        '--material',
        action='store_true',
        default=True,
        help='Generate Material-style colors (default)'
    )
    style_group.add_argument(
        '--default',
        action='store_true',
        help='Generate simpler accent-based palette'
    )
    
    # Theme mode (mutually exclusive)
    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        '--dark',
        action='store_true',
        help='Generate dark theme only'
    )
    mode_group.add_argument(
        '--light',
        action='store_true',
        help='Generate light theme only'
    )
    mode_group.add_argument(
        '--both',
        action='store_true',
        default=True,
        help='Generate both dark and light themes (default)'
    )
    
    parser.add_argument(
        '--output', '-o',
        type=Path,
        help='Write JSON output to file (stdout if omitted)'
    )
    
    parser.add_argument(
        '--render', '-r',
        action='append',
        help='Render a template (input_path:output_path)'
    )
    
    # Matugen compatibility arguments
    parser.add_argument(
        '--config', '-c',
        type=Path,
        help='Path to Matugen TOML configuration file'
    )
    parser.add_argument(
        '--mode',
        choices=['dark', 'light'],
        help='Override theme mode (for Matugen compatibility)'
    )
    parser.add_argument(
        '--type', '-t',
        help='Scheme type (ignored, for Matugen compatibility)'
    )
    
    return parser.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()
    
    # Validate image path
    if not args.image.exists():
        print(f"Error: Image not found: {args.image}", file=sys.stderr)
        return 1
    
    
    # Initialize result dictionary
    result: dict[str, dict[str, str]] = {}

    # Check if input is a JSON palette (Predefined Scheme bypass)
    if args.image.suffix.lower() == '.json':
        try:
            with open(args.image, 'r') as f:
                input_data = json.load(f)
            
            # Expect {"colors": ...} or direct dict
            colors_data = input_data.get("colors", input_data)
            
            # Flatten QML-style object structure if needed
            # structure: key -> { default: { hex: "#..." } } or key -> "#..."
            flat_colors = {}
            for k, v in colors_data.items():
                if isinstance(v, dict) and 'default' in v and 'hex' in v['default']:
                    flat_colors[k] = v['default']['hex']
                elif isinstance(v, str):
                    flat_colors[k] = v
                else:
                    # Best effort fallback
                    flat_colors[k] = str(v)
            
            # Assign to both/all modes since predefined scheme usually provides the correct palette for the requested mode
            result["dark"] = flat_colors
            result["light"] = flat_colors
            
            # Skip extraction logic
            palette = None 
        except Exception as e:
            print(f"Error reading JSON palette: {e}", file=sys.stderr)
            return 1
    else:
        # Standard Image Extraction
        # Validate image path is a file
        if not args.image.is_file():
             print(f"Error: Not a file: {args.image}", file=sys.stderr)
             return 1

        # Read image
        try:
            pixels = read_image(args.image)
        except ImageReadError as e:
            print(f"Error reading image: {e}", file=sys.stderr)
            return 1
        except Exception as e:
            print(f"Unexpected error reading image: {e}", file=sys.stderr)
            return 1
        
        # Extract palette
        k = 5
        palette = extract_palette(pixels, k=k)
        
        if not palette:
            print("Error: Could not extract colors from image", file=sys.stderr)
            return 1
    
    # Determine which themes to generate
    use_material = not args.default
    
    # Handle --mode compatibility
    arg_dark = args.dark
    arg_light = args.light
    arg_both = args.both
    
    if args.mode == 'dark':
        arg_dark = True
        arg_light = False
        arg_both = False
    elif args.mode == 'light':
        arg_dark = False
        arg_light = True
        arg_both = False
    
    
    if palette:
        if arg_dark:
            result["dark"] = generate_theme(palette, "dark", use_material)
        elif arg_light:
            result["light"] = generate_theme(palette, "light", use_material)
        else:
            # Generate both (default)
            result["dark"] = generate_theme(palette, "dark", use_material)
            result["light"] = generate_theme(palette, "light", use_material)
    
    # Output JSON
    json_output = json.dumps(result, indent=2)
    
    if args.output:
        try:
            args.output.write_text(json_output)
            print(f"Theme written to: {args.output}", file=sys.stderr)
        except IOError as e:
            print(f"Error writing output: {e}", file=sys.stderr)
            return 1
    elif not args.render and not args.config:
        print(json_output)
    
    # Process templates
    if args.render or args.config:
        renderer = TemplateRenderer(result)
        
        if args.render:
            for render_spec in args.render:
                if ':' not in render_spec:
                    print(f"Error: Invalid render spec (must be input:output): {render_spec}", file=sys.stderr)
                    continue
                
                input_str, output_str = render_spec.split(':', 1)
                input_path = Path(input_str).expanduser()
                output_path = Path(output_str).expanduser()
                
                if not input_path.exists():
                    print(f"Error: Template not found: {input_path}", file=sys.stderr)
                    continue
                    
                renderer.render_file(input_path, output_path)
                
        if args.config:
            if not args.config.exists():
                 print(f"Error: Config file not found: {args.config}", file=sys.stderr)
            else:
                 renderer.process_config_file(args.config)
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
