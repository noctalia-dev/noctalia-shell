#!/usr/bin/env python3
"""
Analyze Noctalia's template-processor color extraction.

Usage:
    ./template-processor-analysis.py <wallpaper_path>
    ./template-processor-analysis.py ~/Pictures/Wallpapers/example.png

Shows extracted colors for all scheme types and compares M3 schemes with matugen.

Scheme types:
- M3 schemes (tonal-spot, fruit-salad, rainbow, content): Compared with matugen
- vibrant: Prioritizes the most saturated colors regardless of area
- faithful: Prioritizes dominant colors by area coverage
- dysfunctional: Like faithful but picks the 2nd most dominant color family
- muted: Preserves hue but caps saturation low (for monochrome wallpapers)
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

# Add the theming lib to path
SCRIPT_DIR = Path(__file__).parent.resolve()
THEMING_DIR = SCRIPT_DIR.parent / "python" / "src" / "theming"
sys.path.insert(0, str(THEMING_DIR))

from lib.color import Color
from lib.hct import Hct


def hue_diff(h1: float, h2: float) -> float:
    """Calculate circular hue difference."""
    diff = abs(h1 - h2)
    return min(diff, 360.0 - diff)


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    """Convert hex to RGB tuple."""
    h = hex_color.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))


def rgb_distance(hex1: str, hex2: str) -> float:
    """Calculate Euclidean RGB distance (0-441 range)."""
    r1, g1, b1 = hex_to_rgb(hex1)
    r2, g2, b2 = hex_to_rgb(hex2)
    return ((r1-r2)**2 + (g1-g2)**2 + (b1-b2)**2) ** 0.5


def get_hct(hex_color: str) -> Hct:
    """Convert hex color to HCT."""
    return Color.from_hex(hex_color).to_hct()


def hue_to_name(hue: float) -> str:
    """Convert hue to color name."""
    if hue < 30 or hue >= 330:
        return "RED"
    elif hue < 60:
        return "ORANGE"
    elif hue < 90:
        return "YELLOW"
    elif hue < 150:
        return "GREEN"
    elif hue < 210:
        return "CYAN"
    elif hue < 270:
        return "BLUE"
    elif hue < 330:
        return "PURPLE"
    return "RED"


def run_our_processor(image_path: Path, scheme: str) -> dict | None:
    """Run our template-processor and return colors."""
    cmd = [
        sys.executable,
        str(THEMING_DIR / "template-processor.py"),
        str(image_path),
        "--scheme-type", scheme,
        "--dark"
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        return data.get("dark", {})
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"Error running our processor: {e}", file=sys.stderr)
        return None


def run_matugen(image_path: Path, scheme: str) -> dict | None:
    """Run matugen and return colors."""
    matugen_scheme = f"scheme-{scheme}"
    cmd = [
        "matugen", "image", str(image_path),
        "--json", "hex",
        "--dry-run",
        "-t", matugen_scheme
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(result.stdout)
        colors = data.get("colors", {})
        # Extract dark mode values
        return {k: v.get("dark", v) for k, v in colors.items() if isinstance(v, dict)}
    except subprocess.CalledProcessError as e:
        print(f"Error running matugen: {e}", file=sys.stderr)
        return None
    except json.JSONDecodeError as e:
        print(f"Error parsing matugen output: {e}", file=sys.stderr)
        return None


def analyze_vibrant_faithful_muted(image_path: Path) -> None:
    """Analyze vibrant, faithful, dysfunctional, and muted mode outputs."""
    print("\n" + "=" * 78)
    print("VIBRANT vs FAITHFUL vs DYSFUNCTIONAL vs MUTED COMPARISON")
    print("=" * 78)
    print()
    print("Vibrant:      Prioritizes the most saturated colors regardless of area")
    print("Faithful:     Prioritizes dominant colors by area coverage")
    print("Dysfunctional: Like faithful but picks 2nd most dominant color family")
    print("Muted:        Preserves hue but caps saturation low (monochrome wallpapers)")
    print()
    print("-" * 78)
    print(f"{'Mode':<14} {'Color':<12} {'Hex':<10} {'Hue':>8} {'Chroma':>8}  {'Name':<10}")
    print("-" * 78)

    for scheme in ["vibrant", "faithful", "dysfunctional", "muted"]:
        colors = run_our_processor(image_path, scheme)
        if not colors:
            print(f"{scheme}: Failed to get colors")
            continue

        for key in ["primary", "secondary", "tertiary"]:
            hex_color = colors.get(key, "")
            if not hex_color:
                continue

            try:
                hct = get_hct(hex_color)
                name = hue_to_name(hct.hue)
                print(f"{scheme:<14} {key:<12} {hex_color:<10} {hct.hue:>7.1f}° {hct.chroma:>7.1f}  {name:<10}")
            except Exception as e:
                print(f"{scheme:<14} {key:<12} Error: {e}")

        print("-" * 78)

    # Summary comparison
    vibrant = run_our_processor(image_path, "vibrant")
    faithful = run_our_processor(image_path, "faithful")
    dysfunctional = run_our_processor(image_path, "dysfunctional")
    muted = run_our_processor(image_path, "muted")

    if vibrant and faithful and dysfunctional and muted:
        print()
        print("Summary:")
        v_hct = get_hct(vibrant.get("primary", "#000000"))
        f_hct = get_hct(faithful.get("primary", "#000000"))
        d_hct = get_hct(dysfunctional.get("primary", "#000000"))
        m_hct = get_hct(muted.get("primary", "#000000"))

        v_name = hue_to_name(v_hct.hue)
        f_name = hue_to_name(f_hct.hue)
        d_name = hue_to_name(d_hct.hue)
        m_name = hue_to_name(m_hct.hue)

        vf_diff = hue_diff(v_hct.hue, f_hct.hue)
        fd_diff = hue_diff(f_hct.hue, d_hct.hue)

        print(f"  Vibrant primary:      {vibrant.get('primary')} ({v_name}, hue {v_hct.hue:.0f}°, chroma {v_hct.chroma:.1f})")
        print(f"  Faithful primary:     {faithful.get('primary')} ({f_name}, hue {f_hct.hue:.0f}°, chroma {f_hct.chroma:.1f})")
        print(f"  Dysfunctional primary:{dysfunctional.get('primary')} ({d_name}, hue {d_hct.hue:.0f}°, chroma {d_hct.chroma:.1f})")
        print(f"  Muted primary:        {muted.get('primary')} ({m_name}, hue {m_hct.hue:.0f}°, chroma {m_hct.chroma:.1f})")
        print(f"  V-F hue diff:         {vf_diff:.1f}°")
        print(f"  F-D hue diff:         {fd_diff:.1f}°")

        if vf_diff > 60:
            print(f"  → Vibrant/Faithful picked DIFFERENT color families ({v_name} vs {f_name})")
        else:
            print(f"  → Vibrant/Faithful picked SIMILAR colors")

        if fd_diff > 30:
            print(f"  → Faithful/Dysfunctional picked DIFFERENT color families ({f_name} vs {d_name})")
        else:
            print(f"  → Faithful/Dysfunctional picked SIMILAR colors (may only have 1 dominant family)")

        # Note the muted chroma reduction
        if m_hct.chroma < 20:
            print(f"  → Muted successfully reduced chroma to {m_hct.chroma:.1f}")
        else:
            print(f"  → Muted chroma still moderately high ({m_hct.chroma:.1f})")


def compare_m3_schemes(image_path: Path, has_matugen: bool) -> None:
    """Compare all M3 schemes between our processor and matugen."""
    schemes = ["tonal-spot", "fruit-salad", "rainbow", "content", "monochrome"]
    color_keys = ["primary", "secondary", "tertiary", "surface", "on_surface"]

    print("\n" + "=" * 78)
    print("M3 SCHEMES" + (" (compared with matugen)" if has_matugen else ""))
    print("=" * 78)

    if has_matugen:
        # Header for comparison mode
        print(f"{'Scheme':<12} {'Color':<14} {'Ours':<10} {'Matugen':<10} {'Diff':>10}  {'Match':<10}")
        print("-" * 78)

        for scheme in schemes:
            ours = run_our_processor(image_path, scheme)
            matugen = run_matugen(image_path, scheme)

            if not ours or not matugen:
                print(f"{scheme}: Failed to get colors")
                continue

            for key in color_keys:
                our_hex = ours.get(key, "")
                mat_hex = matugen.get(key, "")

                if not our_hex or not mat_hex:
                    continue

                try:
                    our_hct = get_hct(our_hex)
                    mat_hct = get_hct(mat_hex)
                    avg_chroma = (our_hct.chroma + mat_hct.chroma) / 2

                    # For low-chroma colors, use RGB distance instead of hue
                    if avg_chroma < 15:
                        rgb_dist = rgb_distance(our_hex, mat_hex)
                        if rgb_dist < 10:
                            match = "excellent"
                        elif rgb_dist < 25:
                            match = "good"
                        elif rgb_dist < 50:
                            match = "fair"
                        else:
                            match = "poor"
                        diff_str = f"{rgb_dist:>5.1f} rgb"
                    else:
                        diff = hue_diff(our_hct.hue, mat_hct.hue)
                        if diff < 5:
                            match = "excellent"
                        elif diff < 15:
                            match = "good"
                        elif diff < 30:
                            match = "fair"
                        else:
                            match = "poor"
                        diff_str = f"{diff:>5.1f} hue"

                    print(f"{scheme:<12} {key:<14} {our_hex:<10} {mat_hex:<10} {diff_str:>10}  {match:<10}")
                except Exception as e:
                    print(f"{scheme:<12} {key:<14} Error: {e}")

            print("-" * 78)
    else:
        # Header for standalone mode
        print(f"{'Scheme':<12} {'Color':<14} {'Hex':<10} {'Hue':>8} {'Chroma':>8}  {'Name':<10}")
        print("-" * 78)

        for scheme in schemes:
            ours = run_our_processor(image_path, scheme)

            if not ours:
                print(f"{scheme}: Failed to get colors")
                continue

            for key in ["primary", "secondary", "tertiary"]:
                our_hex = ours.get(key, "")
                if not our_hex:
                    continue

                try:
                    hct = get_hct(our_hex)
                    name = hue_to_name(hct.hue)
                    print(f"{scheme:<12} {key:<14} {our_hex:<10} {hct.hue:>7.1f}° {hct.chroma:>7.1f}  {name:<10}")
                except Exception as e:
                    print(f"{scheme:<12} {key:<14} Error: {e}")

            print("-" * 78)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Analyze Noctalia template-processor color extraction"
    )
    parser.add_argument(
        "wallpaper",
        type=Path,
        help="Path to wallpaper image"
    )
    parser.add_argument(
        "--no-matugen",
        action="store_true",
        help="Skip matugen comparison"
    )

    args = parser.parse_args()

    if not args.wallpaper.exists():
        print(f"Error: File not found: {args.wallpaper}", file=sys.stderr)
        return 1

    print(f"\nAnalyzing: {args.wallpaper.name}")

    # Check if matugen is available
    has_matugen = False
    if not args.no_matugen:
        try:
            subprocess.run(["matugen", "--version"], capture_output=True, check=True)
            has_matugen = True
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("Note: matugen not found, skipping M3 comparison")

    # Always show vibrant vs faithful vs muted first (most useful)
    analyze_vibrant_faithful_muted(args.wallpaper)

    # Then show M3 schemes
    compare_m3_schemes(args.wallpaper, has_matugen)

    return 0


if __name__ == "__main__":
    sys.exit(main())
