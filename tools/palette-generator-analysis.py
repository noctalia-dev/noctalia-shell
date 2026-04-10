#!/usr/bin/env python3
"""
Analyze Noctalia's C++ palette generator against Python + matugen references.

Usage:
    ./tools/palette-generator-analysis.py <wallpaper>
    ./tools/palette-generator-analysis.py <wallpaper> --fail-threshold 20

Three backends:
  - Noctalia  : ../build-debug/noctalia theme <img> --scheme <s> --dark
  - Python    : the upstream reference in noctalia-shell/Scripts/python
  - Matugen   : Rust reference (M3 schemes only)

Exit code: 0 if all diffs are under --fail-threshold (default: unlimited),
           1 on failure or threshold exceeded.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent.resolve()
REPO_DIR = SCRIPT_DIR.parent
NOCTALIA_BIN = REPO_DIR / "build-debug" / "noctalia"

# Absolute path into the upstream Python reference.
PYTHON_THEMING_DIR = Path.home() / "Development/misc/noctalia/noctalia-shell/Scripts/python/src/theming"
PYTHON_PROCESSOR = PYTHON_THEMING_DIR / "template-processor.py"

# Pull in Python's Hct for hue/chroma classification.
sys.path.insert(0, str(PYTHON_THEMING_DIR))
try:
    from lib.color import Color  # noqa: E402
    from lib.hct import Hct  # noqa: E402
except ImportError:
    Color = None
    Hct = None

M3_SCHEMES = ["m3-tonal-spot", "m3-fruit-salad", "m3-rainbow", "m3-content", "m3-monochrome"]
CUSTOM_SCHEMES = ["vibrant", "faithful", "dysfunctional", "muted"]


def python_scheme_name(scheme: str) -> str:
    """Translate our m3-* names to what the upstream Python processor expects."""
    return scheme[3:] if scheme.startswith("m3-") else scheme


def matugen_scheme_name(scheme: str) -> str:
    return scheme[3:] if scheme.startswith("m3-") else scheme
KEY_TOKENS = ["primary", "secondary", "tertiary", "surface", "on_surface",
              "primary_container", "surface_container", "outline"]


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip('#')
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgb_distance(a: str, b: str) -> float:
    r1, g1, b1 = hex_to_rgb(a)
    r2, g2, b2 = hex_to_rgb(b)
    return ((r1 - r2) ** 2 + (g1 - g2) ** 2 + (b1 - b2) ** 2) ** 0.5


def max_lsb(a: str, b: str) -> int:
    r1, g1, b1 = hex_to_rgb(a)
    r2, g2, b2 = hex_to_rgb(b)
    return max(abs(r1 - r2), abs(g1 - g2), abs(b1 - b2))


def hue_diff(h1: float, h2: float) -> float:
    d = abs(h1 - h2)
    return min(d, 360.0 - d)


def get_hct(hex_color: str):
    if Color is None:
        return None
    return Color.from_hex(hex_color).to_hct()


def run_python(image: Path, scheme: str) -> dict | None:
    try:
        out = subprocess.run(
            [sys.executable, str(PYTHON_PROCESSOR), str(image),
             "--scheme-type", python_scheme_name(scheme), "--dark"],
            capture_output=True, text=True, check=True,
        )
        data = json.loads(out.stdout)
        return data.get("dark", data)
    except Exception as e:
        print(f"  python {scheme}: {e}", file=sys.stderr)
        return None


def run_matugen(image: Path, scheme: str) -> dict | None:
    try:
        out = subprocess.run(
            ["matugen", "image", str(image), "--json", "hex",
             "--dry-run", "-m", "dark",
             "--source-color-index", "0",
             "--old-json-output",
             "-t", f"scheme-{matugen_scheme_name(scheme)}"],
            capture_output=True, text=True, check=True,
        )
        data = json.loads(out.stdout)
        colors = data.get("colors", {})
        # Each entry is {"dark": "#hex", "default": "#hex", "light": "#hex"}.
        return {k: v.get("dark", v) for k, v in colors.items() if isinstance(v, dict)}
    except Exception as e:
        print(f"  matugen {scheme}: {e}", file=sys.stderr)
        return None


def run_noctalia(image: Path, scheme: str) -> dict | None:
    try:
        out = subprocess.run(
            [str(NOCTALIA_BIN), "theme", str(image),
             "--scheme", scheme, "--dark"],
            capture_output=True, text=True, check=True,
        )
        return json.loads(out.stdout)
    except Exception as e:
        print(f"  noctalia {scheme}: {e}", file=sys.stderr)
        return None


def quality_bucket(our: str, ref: str) -> tuple[str, str]:
    """Return (metric_str, bucket) using hue for high-chroma, RGB for low."""
    try:
        h1 = get_hct(our)
        h2 = get_hct(ref)
        avg = (h1.chroma + h2.chroma) / 2
    except Exception:
        avg = 0

    if avg < 15:
        d = rgb_distance(our, ref)
        bucket = "excellent" if d < 10 else "good" if d < 25 else "fair" if d < 50 else "poor"
        return f"{d:5.1f} rgb", bucket
    else:
        d = hue_diff(h1.hue, h2.hue)
        bucket = "excellent" if d < 5 else "good" if d < 15 else "fair" if d < 30 else "poor"
        return f"{d:5.1f} hue", bucket


def compare_m3(image: Path, scheme: str, has_matugen: bool) -> list[int]:
    """Return list of LSB diffs vs the best available reference."""
    print(f"\n─── {scheme} ───")
    py = run_python(image, scheme)
    noct = run_noctalia(image, scheme)
    mat = run_matugen(image, scheme) if has_matugen else None

    if not py or not noct:
        print("  ! missing reference output, skipping")
        return []

    hdr = f"  {'Token':<26} {'Python':<10} {'Matugen':<10} {'Noctalia':<10} {'Δ Py↔Noct':<14} {'Δ Mat↔Noct':<14}"
    print(hdr)
    print("  " + "─" * (len(hdr) - 2))

    diffs: list[int] = []
    for token in KEY_TOKENS:
        pv = py.get(token, "")
        nv = noct.get(token, "")
        mv = (mat or {}).get(token, "")
        if not (pv and nv):
            continue

        py_noct_metric, py_noct_bucket = quality_bucket(nv, pv)
        if mv:
            mat_noct_metric, mat_noct_bucket = quality_bucket(nv, mv)
            mat_col = f"{mat_noct_metric} {mat_noct_bucket[:4]}"
        else:
            mat_col = "-"

        lsb = max_lsb(pv, nv)
        diffs.append(lsb)

        print(f"  {token:<26} {pv:<10} {mv or '-':<10} {nv:<10} "
              f"{py_noct_metric} {py_noct_bucket[:4]:<5} {mat_col:<14}  "
              f"(Δ{lsb})")
    return diffs


def compare_custom(image: Path, scheme: str) -> list[int]:
    print(f"\n─── {scheme} ───")
    py = run_python(image, scheme)
    noct = run_noctalia(image, scheme)
    if not py or not noct:
        print("  ! missing reference output, skipping")
        return []

    hdr = f"  {'Token':<26} {'Python':<10} {'Noctalia':<10} {'Δ Py↔Noct':<14}"
    print(hdr)
    print("  " + "─" * (len(hdr) - 2))

    diffs: list[int] = []
    for token in KEY_TOKENS:
        pv = py.get(token, "")
        nv = noct.get(token, "")
        if not (pv and nv):
            continue
        metric, bucket = quality_bucket(nv, pv)
        lsb = max_lsb(pv, nv)
        diffs.append(lsb)
        print(f"  {token:<26} {pv:<10} {nv:<10} "
              f"{metric} {bucket[:4]:<5}  (Δ{lsb})")
    return diffs


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare Noctalia C++ palette generator vs Python/matugen"
    )
    parser.add_argument("wallpaper", type=Path)
    parser.add_argument("--fail-threshold", type=int, default=-1,
                        help="Exit 1 if any token's max-channel LSB diff exceeds N")
    parser.add_argument("--no-matugen", action="store_true")
    parser.add_argument("--schemes", nargs="+",
                        help="Limit to a subset of schemes")
    args = parser.parse_args()

    if not args.wallpaper.exists():
        print(f"error: not found: {args.wallpaper}", file=sys.stderr)
        return 1
    if not NOCTALIA_BIN.exists():
        print(f"error: noctalia not built: {NOCTALIA_BIN}", file=sys.stderr)
        return 1

    has_matugen = False
    if not args.no_matugen:
        try:
            subprocess.run(["matugen", "--version"], capture_output=True, check=True)
            has_matugen = True
        except Exception:
            print("note: matugen not available, skipping its column")

    print(f"\nWallpaper: {args.wallpaper.name}")
    print("=" * 78)
    print("M3 SCHEMES (Python is a MCU port; Matugen is the Rust reference)")
    print("=" * 78)

    all_diffs: list[tuple[str, int]] = []

    m3 = M3_SCHEMES if not args.schemes else [s for s in M3_SCHEMES if s in args.schemes]
    for s in m3:
        for d in compare_m3(args.wallpaper, s, has_matugen):
            all_diffs.append((s, d))

    print()
    print("=" * 78)
    print("CUSTOM SCHEMES (Python is the only reference)")
    print("=" * 78)

    custom = CUSTOM_SCHEMES if not args.schemes else [s for s in CUSTOM_SCHEMES if s in args.schemes]
    for s in custom:
        for d in compare_custom(args.wallpaper, s):
            all_diffs.append((s, d))

    print()
    print("─" * 78)
    print("Summary")
    per_scheme: dict[str, list[int]] = {}
    for s, d in all_diffs:
        per_scheme.setdefault(s, []).append(d)
    for s in list(per_scheme):
        ds = per_scheme[s]
        if ds:
            print(f"  {s:<14} max Δ={max(ds):>3}  mean Δ={sum(ds)/len(ds):>5.1f}  ({len(ds)} tokens)")

    if args.fail_threshold >= 0:
        worst = max((d for _, d in all_diffs), default=0)
        if worst > args.fail_threshold:
            print(f"\nFAIL: worst Δ={worst} > threshold {args.fail_threshold}")
            return 1
        print(f"\nOK: worst Δ={worst} ≤ threshold {args.fail_threshold}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
