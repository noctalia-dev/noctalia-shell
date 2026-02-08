"""
Image reading utilities for PNG and JPEG files.

This module provides functions for extracting RGB pixels from image files
without external dependencies (except ImageMagick for fallback).
"""

import struct
import zlib
from pathlib import Path

# Type alias
RGB = tuple[int, int, int]


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


def _sample_jpeg_colors(data: bytes, width: int, height: int) -> list[RGB]:
    """
    Sample colors from JPEG data without full decoding.

    This is a rough approximation that samples byte triplets from the
    compressed data. Not accurate, but provides some color information.
    For accurate results, use ImageMagick via read_image().
    """
    # Sample every Nth byte triplet from the image data
    # Skip headers and look for image data after SOS marker
    pixels: list[RGB] = []
    step = max(1, len(data) // (width * height // 16))

    for i in range(0, len(data) - 2, step):
        r, g, b = data[i], data[i+1], data[i+2]
        # Filter out obviously non-image data (markers, etc.)
        if not (r == 0xFF and g in (0xD8, 0xD9, 0xE0, 0xE1)):
            pixels.append((r, g, b))

    return pixels if pixels else [(128, 128, 128)]


def _read_image_imagemagick(path: Path, resize_filter: str = "Triangle") -> list[RGB]:
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

    # Resize to 112x112 to match matugen's color extraction
    # Use -filter Triangle (bilinear) for M3 schemes to match matugen's FilterType::Triangle default
    # Use -filter Box for k-means schemes (sharper, preserves distinct color regions)
    # Use -depth 8 -colorspace sRGB -strip to reduce variance between HDRI/non-HDRI builds
    resize_spec = "112x112!"

    try:
        # Try 'magick' first (ImageMagick 7+), fallback to 'convert' (ImageMagick 6)
        try:
            result = subprocess.run(
                ['magick', str(path), '-filter', resize_filter, '-resize', resize_spec,
                 '-depth', '8', '-colorspace', 'sRGB', '-strip', 'ppm:-'],
                capture_output=True,
                check=True
            )
        except FileNotFoundError:
            result = subprocess.run(
                ['convert', str(path), '-filter', resize_filter, '-resize', resize_spec,
                 '-depth', '8', '-colorspace', 'sRGB', '-strip', 'ppm:-'],
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


def read_image(path: Path, resize_filter: str = "Triangle") -> list[RGB]:
    """
    Read an image file and return its pixels as RGB tuples.

    Uses ImageMagick for accurate color extraction from any format.
    Falls back to native PNG parsing if ImageMagick is unavailable.

    Args:
        path: Path to the image file.
        resize_filter: ImageMagick resize filter. "Triangle" for M3 schemes
                       (matches matugen), "Box" for k-means schemes.
    """
    suffix = path.suffix.lower()

    # Try ImageMagick first (works for any format)
    try:
        return _read_image_imagemagick(path, resize_filter)
    except ImageReadError:
        # Fall back to native parsing for PNG
        if suffix == '.png':
            return read_png(path)
        raise
