#!/usr/bin/env python3
"""
Noctalia's Template processor - Wallpaper-based color extraction and theme generation.

A CLI tool that extracts dominant colors from wallpaper images and generates palettes with optional templating.

Supported scheme types:
- tonal-spot: Default Android 12-13 Material You scheme (recommended)
- content: Preserves source color's chroma with temperature-based tertiary (matugen default)
- fruit-salad: Bold/playful with -50° hue rotation
- rainbow: Chromatic accents with grayscale neutrals
- monochrome: Pure grayscale M3 scheme (chroma = 0, only error has color)
- vibrant: Prioritizes the most saturated colors regardless of area coverage
- faithful: Prioritizes dominant colors by area, what you see is what you get
- dysfunctional: Like faithful but picks the 2nd most dominant color family
- muted: Preserves hue but caps saturation low (for monochrome/monotonal wallpapers)

Usage:
    python3 template-processor.py IMAGE_OR_JSON [OPTIONS]

Options:
    --scheme-type    Scheme type: tonal-spot (default), content, fruit-salad, rainbow, monochrome, vibrant, faithful, dysfunctional, muted
    --dark           Generate dark theme only
    --light          Generate light theme only
    --both           Generate both themes (default)
    -o, --output     Write JSON output to file (stdout if omitted)
    -r, --render     Render a template (input_path:output_path)
    -c, --config     Path to TOML configuration file with template definitions
    --mode           Theme mode: dark or light

Input:
    Can be an image file (PNG/JPG) or a JSON color palette file.

Example:
    python3 template-processor.py ~/wallpaper.png --scheme-type tonal-spot
    python3 template-processor.py ~/wallpaper.png --scheme-type fruit-salad --dark
    python3 template-processor.py ~/wallpaper.jpg --dark -o theme.json
    python3 template-processor.py ~/wallpaper.png -r template.txt:output.txt
    python3 template-processor.py ~/wallpaper.png -c config.toml --mode dark

Author: Noctalia Team
License: MIT
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Import from lib package
from lib import (
    read_image, ImageReadError, extract_palette, generate_theme,
    TemplateRenderer, expand_predefined_scheme,
    extract_source_color, source_color_to_rgb, Color,
)
from lib.scheme import inject_terminal_colors


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        prog='template-processor',
        description='Extract color palettes from wallpapers and generate themes',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 template-processor.py wallpaper.png                                      # tonal-spot (default), both themes
  python3 template-processor.py wallpaper.png --scheme-type content --dark         # content scheme, dark only
  python3 template-processor.py wallpaper.jpg --dark -o theme.json                 # output to file
  python3 template-processor.py wallpaper.png -r template.txt:output.txt           # render template
  python3 template-processor.py wallpaper.png -c config.toml --mode dark           # render config, dark only
        """
    )

    parser.add_argument(
        'image',
        type=Path,
        nargs='?',
        help='Path to wallpaper image (PNG/JPG) or JSON color palette (not required if --scheme is used)'
    )

    # Scheme type selection
    parser.add_argument(
        '--scheme-type',
        choices=['tonal-spot', 'content', 'fruit-salad', 'rainbow', 'monochrome', 'vibrant', 'faithful', 'dysfunctional', 'muted'],
        default='tonal-spot',
        help='Color scheme type (default: tonal-spot)'
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

    parser.add_argument(
        '--config', '-c',
        type=Path,
        help='Path to TOML configuration file with template definitions'
    )
    parser.add_argument(
        '--mode',
        choices=['dark', 'light'],
        help='Theme mode: dark or light'
    )

    parser.add_argument(
        '--scheme',
        type=Path,
        help='Path to predefined scheme JSON file (bypasses image extraction)'
    )

    parser.add_argument(
        '--default-mode',
        choices=['dark', 'light'],
        default='dark',
        help='Theme mode to use for "default" in templates (default: dark)'
    )

    return parser.parse_args()


# M3 schemes use Triangle filter (matches matugen); others use Box for k-means
_M3_SCHEMES = {"tonal-spot", "content", "fruit-salad", "rainbow", "monochrome"}

# K-means-based schemes and their scoring strategy
_KMEANS_SCORING: dict[str, str] = {
    "vibrant": "chroma",
    "faithful": "count",
    "dysfunctional": "dysfunctional",
    "muted": "muted",
}


def _determine_modes(args: argparse.Namespace) -> list[str]:
    if args.mode in ('dark', 'light'):
        return [args.mode]
    if args.dark:
        return ["dark"]
    if args.light:
        return ["light"]
    return ["dark", "light"]


def _load_scheme_file(path: Path, modes: list[str]) -> "dict[str, dict[str, str]] | int":
    if not path.exists():
        print(f"Error: Scheme file not found: {path}", file=sys.stderr)
        return 1
    try:
        scheme_data = json.loads(path.read_text())
        result: dict[str, dict[str, str]] = {}
        for mode in modes:
            if mode in scheme_data:
                result[mode] = expand_predefined_scheme(scheme_data[mode], mode)
                inject_terminal_colors(result[mode], scheme_data[mode])
            elif "mPrimary" in scheme_data:
                result[mode] = expand_predefined_scheme(scheme_data, mode)
                inject_terminal_colors(result[mode], scheme_data)
            else:
                print(f"Error: Invalid scheme format - missing '{mode}' or 'mPrimary'", file=sys.stderr)
                return 1
        return result
    except json.JSONDecodeError as e:
        print(f"Error parsing scheme JSON: {e}", file=sys.stderr)
        return 1
    except KeyError as e:
        print(f"Error: Missing required color in scheme: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Error processing scheme: {e}", file=sys.stderr)
        return 1


def _load_json_palette(image_path: Path, modes: list[str]) -> "dict[str, dict[str, str]] | int":
    try:
        input_data = json.loads(image_path.read_text())
        colors_data = input_data.get("colors", input_data)
        # Flatten QML-style structure: key -> { default: { hex: "#..." } } or key -> "#..."
        flat_colors: dict[str, str] = {}
        for k, v in colors_data.items():
            if isinstance(v, dict) and 'default' in v and 'hex' in v['default']:
                flat_colors[k] = v['default']['hex']
            elif isinstance(v, str):
                flat_colors[k] = v
            else:
                flat_colors[k] = str(v)
        return dict.fromkeys(modes, flat_colors)
    except Exception as e:
        print(f"Error reading JSON palette: {e}", file=sys.stderr)
        return 1


def _build_palette_from_pixels(pixels, scheme_type: str):
    scoring = _KMEANS_SCORING.get(scheme_type)
    if scoring:
        return extract_palette(pixels, k=5, scoring=scoring)
    # Wu quantizer + Score algorithm (matches matugen) for M3 schemes
    source_argb = extract_source_color(pixels)
    r, g, b = source_color_to_rgb(source_argb)
    return [Color(r, g, b)]


def _extract_from_image(args: argparse.Namespace, modes: list[str]) -> "dict[str, dict[str, str]] | int":
    if args.image is None:
        print("Error: Image path is required (unless --scheme is used)", file=sys.stderr)
        return 1
    if not args.image.exists():
        print(f"Error: Image not found: {args.image}", file=sys.stderr)
        return 1
    if args.image.suffix.lower() == '.json':
        return _load_json_palette(args.image, modes)
    if not args.image.is_file():
        print(f"Error: Not a file: {args.image}", file=sys.stderr)
        return 1

    scheme_type = args.scheme_type
    resize_filter = "Triangle" if scheme_type in _M3_SCHEMES else "Box"

    try:
        pixels = read_image(args.image, resize_filter)
    except ImageReadError as e:
        print(f"Error reading image: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"Unexpected error reading image: {e}", file=sys.stderr)
        return 1

    palette = _build_palette_from_pixels(pixels, scheme_type)
    if not palette:
        print("Error: Could not extract colors from image", file=sys.stderr)
        return 1

    return {mode: generate_theme(palette, mode, scheme_type) for mode in modes}


def _write_output(args: argparse.Namespace, json_output: str) -> int:
    if args.output:
        try:
            args.output.write_text(json_output)
            print(f"Theme written to: {args.output}", file=sys.stderr)
        except IOError as e:
            print(f"Error writing output: {e}", file=sys.stderr)
            return 1
    elif not args.render and not args.config:
        print(json_output)
    return 0


def _process_templates(args: argparse.Namespace, result: dict) -> None:
    image_path = str(args.image) if args.image else None
    renderer = TemplateRenderer(result, default_mode=args.default_mode, image_path=image_path, scheme_type=args.scheme_type)

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


def main() -> int:
    """Main entry point."""
    args = parse_args()
    modes = _determine_modes(args)

    result = _load_scheme_file(args.scheme, modes) if args.scheme else _extract_from_image(args, modes)
    if isinstance(result, int):
        return result

    rc = _write_output(args, json.dumps(result, indent=2))
    if rc:
        return rc

    if args.render or args.config:
        _process_templates(args, result)

    return 0


if __name__ == '__main__':
    sys.exit(main())
