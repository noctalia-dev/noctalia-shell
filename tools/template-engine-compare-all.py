#!/usr/bin/env python3
"""
Render all official templates through both the legacy Python engine and the
current C++ TemplateEngine, using the same precomputed token map for both.

Usage:
    ./tools/template-engine-compare-all.py <wallpaper>
    ./tools/template-engine-compare-all.py <wallpaper> --scheme muted
"""

from __future__ import annotations

import argparse
import filecmp
import json
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT_DIR = Path(__file__).parent.resolve()
REPO_DIR = SCRIPT_DIR.parent
NOCTALIA_BIN = REPO_DIR / "build-debug" / "noctalia"
PYTHON_PROCESSOR = (
    Path.home() / "Development/misc/noctalia/noctalia-shell/Scripts/python/src/theming/template-processor.py"
)
PYTHON_THEMING_DIR = Path.home() / "Development/misc/noctalia/noctalia-shell/Scripts/python/src/theming"
TEMPLATE_ROOT = Path.home() / "Development/misc/noctalia/noctalia-shell/Assets/Templates"
PREDEFINED_SCHEME_JSON = (
    Path.home() / "Development/misc/noctalia/noctalia-shell/Assets/ColorScheme/Noctalia-default/Noctalia-default.json"
)

sys.path.insert(0, str(PYTHON_THEMING_DIR))
from lib.renderer import TemplateRenderer  # noqa: E402

def render_python(theme_json: Path, template_in: Path, output: Path, default_mode: str) -> tuple[bool, str]:
    try:
        theme_data = json.loads(theme_json.read_text())
        renderer = TemplateRenderer(theme_data, default_mode=default_mode, image_path="", scheme_type="content", verbose=False)
        success, _wrote = renderer.render_file(template_in, output)
        if not success:
          return False, "renderer reported failure"
        if not output.exists():
            return False, "renderer exited successfully but did not produce an output file"
        return True, ""
    except Exception as e:
        return False, str(e)


def render_cpp(theme_json: Path, scheme: str, template_in: Path, output: Path, default_mode: str) -> tuple[bool, str]:
    try:
        subprocess.run(
            [
                str(NOCTALIA_BIN),
                "theme",
                "--theme-json",
                str(theme_json),
                "--scheme",
                scheme,
                "--both",
                "--default-mode",
                default_mode,
                "-r",
                f"{template_in}:{output}",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        if not output.exists():
            return False, "renderer exited successfully but did not produce an output file"
        return True, ""
    except subprocess.CalledProcessError as e:
        return False, e.stderr.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare all official template outputs between Python and C++")
    parser.add_argument("wallpaper", type=Path)
    parser.add_argument("--scheme", default="m3-content")
    parser.add_argument("--default-mode", default="dark", choices=["dark", "light"])
    parser.add_argument("--templates-root", type=Path, default=TEMPLATE_ROOT)
    parser.add_argument("--predefined-scheme-json", type=Path, default=PREDEFINED_SCHEME_JSON)
    parser.add_argument("--show-matches", action="store_true")
    args = parser.parse_args()

    if not args.wallpaper.exists():
        print(f"error: wallpaper not found: {args.wallpaper}", file=sys.stderr)
        return 1
    if not args.templates_root.exists():
        print(f"error: templates root not found: {args.templates_root}", file=sys.stderr)
        return 1
    if not NOCTALIA_BIN.exists():
        print(f"error: noctalia binary not found: {NOCTALIA_BIN}", file=sys.stderr)
        return 1
    if not args.predefined_scheme_json.exists():
        print(f"error: predefined scheme json not found: {args.predefined_scheme_json}", file=sys.stderr)
        return 1

    templates = sorted(path for path in args.templates_root.rglob("*") if path.is_file())
    failures = 0
    compared = 0

    with tempfile.TemporaryDirectory(prefix="template-compare-") as tmp:
        tmp_root = Path(tmp)
        py_root = tmp_root / "python"
        cpp_root = tmp_root / "cpp"
        shared_theme = tmp_root / "shared-theme.json"
        py_root.mkdir()
        cpp_root.mkdir()
        shared_predefined_theme = tmp_root / "shared-predefined-theme.json"

        subprocess.run(
            [
                sys.executable,
                str(PYTHON_PROCESSOR),
                str(args.wallpaper),
                "--scheme-type",
                args.scheme[3:] if args.scheme.startswith("m3-") else args.scheme,
                "--both",
                "-o",
                str(shared_theme),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        subprocess.run(
            [
                sys.executable,
                str(PYTHON_PROCESSOR),
                "--scheme",
                str(args.predefined_scheme_json),
                "--both",
                "-o",
                str(shared_predefined_theme),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        for template in templates:
            rel = template.relative_to(args.templates_root)
            py_out = py_root / rel
            cpp_out = cpp_root / rel
            py_out.parent.mkdir(parents=True, exist_ok=True)
            cpp_out.parent.mkdir(parents=True, exist_ok=True)
            theme_json = shared_predefined_theme if "-predefined" in template.name else shared_theme

            py_ok, py_err = render_python(theme_json, template, py_out, args.default_mode)
            cpp_ok, cpp_err = render_cpp(theme_json, args.scheme, template, cpp_out, args.default_mode)

            compared += 1
            if not py_ok or not cpp_ok:
                failures += 1
                print(f"FAIL {rel}")
                if not py_ok:
                    print(f"  python: {py_err}")
                if not cpp_ok:
                    print(f"  c++: {cpp_err}")
                continue

            if not filecmp.cmp(py_out, cpp_out, shallow=False):
                failures += 1
                print(f"DIFF {rel}")
            elif args.show_matches:
                print(f"OK   {rel}")

    print(f"\nCompared {compared} templates")
    if failures:
        print(f"Failures: {failures}")
        return 1
    print("All outputs match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
