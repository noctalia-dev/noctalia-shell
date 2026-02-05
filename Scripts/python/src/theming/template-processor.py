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
    TerminalColors, TerminalGenerator
)


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

    parser.add_argument(
        '--terminal-output',
        type=str,
        help='JSON mapping of terminal IDs to output paths: {"foot": "/path/to/output", ...}'
    )

    return parser.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()

    # Initialize result dictionary
    result: dict[str, dict[str, str]] = {}

    # Determine mode from arguments
    if args.mode == 'dark':
        modes = ["dark"]
    elif args.mode == 'light':
        modes = ["light"]
    elif args.dark:
        modes = ["dark"]
    elif args.light:
        modes = ["light"]
    else:
        modes = ["dark", "light"]

    # Path 1: Predefined scheme (--scheme flag)
    if args.scheme:
        if not args.scheme.exists():
            print(f"Error: Scheme file not found: {args.scheme}", file=sys.stderr)
            return 1

        try:
            with open(args.scheme, 'r') as f:
                scheme_data = json.load(f)

            # Scheme format: {"dark": {"mPrimary": "#...", ...}, "light": {...}}
            # or single mode: {"mPrimary": "#...", ...}
            for mode in modes:
                if mode in scheme_data:
                    # Multi-mode format
                    result[mode] = expand_predefined_scheme(scheme_data[mode], mode)
                elif "mPrimary" in scheme_data:
                    # Single-mode format - use same colors for requested mode
                    result[mode] = expand_predefined_scheme(scheme_data, mode)
                else:
                    print(f"Error: Invalid scheme format - missing '{mode}' or 'mPrimary'", file=sys.stderr)
                    return 1

        except json.JSONDecodeError as e:
            print(f"Error parsing scheme JSON: {e}", file=sys.stderr)
            return 1
        except KeyError as e:
            print(f"Error: Missing required color in scheme: {e}", file=sys.stderr)
            return 1
        except Exception as e:
            print(f"Error processing scheme: {e}", file=sys.stderr)
            return 1

    # Path 2: Image-based extraction (default)
    else:
        # Validate image argument is provided
        if args.image is None:
            print("Error: Image path is required (unless --scheme is used)", file=sys.stderr)
            return 1

        # Validate image path
        if not args.image.exists():
            print(f"Error: Image not found: {args.image}", file=sys.stderr)
            return 1

        # Check if input is a JSON palette (Predefined Color Scheme)
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

                # Assign to requested modes
                for mode in modes:
                    result[mode] = flat_colors

            except Exception as e:
                print(f"Error reading JSON palette: {e}", file=sys.stderr)
                return 1
        else:
            # Standard Image Extraction
            if not args.image.is_file():
                print(f"Error: Not a file: {args.image}", file=sys.stderr)
                return 1

            try:
                pixels = read_image(args.image)
            except ImageReadError as e:
                print(f"Error reading image: {e}", file=sys.stderr)
                return 1
            except Exception as e:
                print(f"Unexpected error reading image: {e}", file=sys.stderr)
                return 1

            # Determine scheme type
            scheme_type = args.scheme_type

            # Extract palette based on scheme type:
            # - M3 schemes (tonal-spot, fruit-salad, rainbow, content): Use Wu quantizer + Score
            #   This matches matugen's color extraction exactly
            # - vibrant: Use k-means clustering for colorful/blended colors
            # - faithful: Use Wu quantizer for primary (dominant by area), k-means for accents
            # - dysfunctional: Like faithful but picks 2nd most dominant color family
            # - muted: Like count but without chroma filtering (for monochrome wallpapers)
            if scheme_type == "vibrant":
                # K-means with chroma scoring for vibrant, blended colors
                palette = extract_palette(pixels, k=5, scoring="chroma")
            elif scheme_type == "faithful":
                # K-means with count scoring - picks dominant color by area coverage
                # This ensures primary reflects what you actually see in the image
                palette = extract_palette(pixels, k=5, scoring="count")
            elif scheme_type == "dysfunctional":
                # K-means with dysfunctional scoring - picks 2nd most dominant color family
                # For when the dominant color is not what you want as primary
                palette = extract_palette(pixels, k=5, scoring="dysfunctional")
            elif scheme_type == "muted":
                # K-means with muted scoring - accepts low/zero chroma colors
                # For monochrome/monotonal wallpapers where dominant color has low saturation
                palette = extract_palette(pixels, k=5, scoring="muted")
            else:
                # Wu quantizer + Score algorithm (matches matugen)
                source_argb = extract_source_color(pixels)
                r, g, b = source_color_to_rgb(source_argb)
                palette = [Color(r, g, b)]

            if not palette:
                print("Error: Could not extract colors from image", file=sys.stderr)
                return 1

            # Generate theme for each mode
            for mode in modes:
                result[mode] = generate_theme(palette, mode, scheme_type)

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

    # Process terminal output if specified
    if args.terminal_output and args.scheme:
        try:
            terminal_outputs = json.loads(args.terminal_output)
        except json.JSONDecodeError as e:
            print(f"Error parsing --terminal-output JSON: {e}", file=sys.stderr)
            return 1

        # Load scheme to check for terminal section
        with open(args.scheme, 'r') as f:
            scheme_data = json.load(f)

        # Determine which mode to use for terminal colors
        mode = args.default_mode

        # Check if scheme has terminal colors
        mode_data = scheme_data.get(mode, scheme_data)
        if "terminal" not in mode_data:
            print(f"Warning: Scheme has no 'terminal' section for mode '{mode}'", file=sys.stderr)
            return 0

        try:
            # Extract scheme UI colors for derivation (mPrimary, mOnPrimary, mSecondary)
            scheme_colors = {
                "mPrimary": mode_data.get("mPrimary"),
                "mOnPrimary": mode_data.get("mOnPrimary"),
                "mSecondary": mode_data.get("mSecondary"),
            }
            terminal_colors = TerminalColors.from_dict(mode_data["terminal"], scheme_colors)
            generator = TerminalGenerator(terminal_colors)

            for terminal_id, output_path in terminal_outputs.items():
                try:
                    content = generator.generate(terminal_id)
                    output_file = Path(output_path).expanduser()
                    output_file.parent.mkdir(parents=True, exist_ok=True)
                    output_file.write_text(content)
                except ValueError as e:
                    print(f"Error generating {terminal_id}: {e}", file=sys.stderr)
                except IOError as e:
                    print(f"Error writing {output_path}: {e}", file=sys.stderr)

        except KeyError as e:
            print(f"Error: Missing required terminal color: {e}", file=sys.stderr)
            return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
