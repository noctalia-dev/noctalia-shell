#!/usr/bin/env python3
"""
Filter Milkdrop presets at build time.

Removes .milk files that are too bright or contain rapidly flashing patterns.
Keeps presets that score below the brightness threshold and flash threshold.

Usage: filter-presets.py <presets-dir>
"""

import os
import re
import sys


def is_preset_safe(path: str) -> bool:
    """Return True if the preset is dark/safe enough to keep."""
    try:
        with open(path, "r", errors="replace") as f:
            content = f.read()
    except OSError:
        return True  # can't read → keep

    # Parse key=value pairs and collect code sections
    params: dict[str, float] = {}
    per_frame_code = ""   # global per-frame and per-pixel equations
    per_point_code = ""   # wave/shape per-point code (per-element, not global)
    shader_code = ""

    for line in content.splitlines():
        line = line.strip()
        if "=" not in line or line.startswith("//") or line.startswith("["):
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()

        # Collect global per-frame/per-pixel code
        if key.startswith(("per_frame_", "per_pixel_")):
            # Strip // comments (Milkdrop per-frame comment syntax)
            code_val = re.sub(r"//.*", "", val)
            per_frame_code += code_val + "\n"
            continue

        # Collect wave/shape per-frame code (global timing)
        if re.match(r"(wave|shape)_\d+_per_frame\d+", key):
            code_val = re.sub(r"//.*", "", val)
            per_frame_code += code_val + "\n"
            continue

        # Collect wave/shape per-point code separately (per-element effects)
        if re.match(r"(wave|shape)_\d+_per_point\d+", key):
            code_val = re.sub(r"//.*", "", val)
            per_point_code += code_val + "\n"
            continue

        # Collect shader code (warp_N, comp_N)
        if re.match(r"(warp|comp)_\d+", key):
            # Strip leading backtick used in .milk shader lines
            # Strip // comments
            code_val = re.sub(r"//.*", "", val.lstrip("`"))
            shader_code += code_val + "\n"
            continue

        try:
            params[key] = float(val)
        except ValueError:
            pass

    # --- Brightness score ---
    bright = 0.0
    bright += (params.get("fGammaAdj", 1.0) - 1.0) * 2.0

    if params.get("bBrighten", 0) > 0:
        bright += 3.0
    if params.get("bDarken", 0) > 0:
        bright -= 2.0
    if params.get("bSolarize", 0) > 0:
        bright += 2.0
    if params.get("bInvert", 0) > 0:
        bright += 1.5
    if params.get("bAdditiveWaves", 0) > 0:
        bright += 0.5
    if params.get("bDarkenCenter", 0) > 0:
        bright -= 0.5

    decay = params.get("fDecay", 0.98)
    if decay > 0.999:
        bright += 1.0
    elif decay < 0.9:
        bright -= 1.0

    if params.get("fVideoEchoAlpha", 0) > 0.5:
        bright += 1.0

    wave_avg = (
        params.get("wave_r", 0) + params.get("wave_g", 0) + params.get("wave_b", 0)
    ) / 3.0
    if wave_avg > 0.7:
        bright += 1.0

    for i in range(4):
        pfx = f"shapecode_{i}_"
        if (
            params.get(pfx + "enabled", 0) > 0
            and params.get(pfx + "a", 0) > 0.5
            and (
                params.get(pfx + "r", 0)
                + params.get(pfx + "g", 0)
                + params.get(pfx + "b", 0)
            )
            / 3.0
            > 0.8
        ):
            bright += 1.0

    if bright >= 3.0:
        return False

    # --- Crash guard: sampler_rand0X textures ---
    # projectM requires a texture search path for sampler_rand01..04 to be
    # resolved.  When no path is configured the Texture* is null; any preset
    # whose warp or comp shader declares or uses sampler_rand0X will crash
    # inside MilkdropShader::LoadVariables (SIGSEGV on Texture::Empty()).
    if re.search(r"sampler_rand0\d", shader_code, re.IGNORECASE):
        return False

    # --- Flash score ---
    # Analyze both per-frame code AND shader code for flash patterns
    flash = 0.0
    all_code = (per_frame_code + "\n" + shader_code).lower()
    pf = per_frame_code.lower()
    sh = shader_code.lower()

    # -- Per-frame flash patterns --

    # Rapid sin(time*N) — photosensitive danger zone is 3-60 Hz.
    # sin(time*N) cycles at N/(2*pi) Hz, so N=20 ≈ 3.2Hz, N=40 ≈ 6.4Hz.
    for m in re.finditer(r"sin\s*\(\s*time\s*\*\s*(\d+\.?\d*)", pf):
        freq = float(m.group(1))
        if freq > 40:
            flash += 2.0
        elif freq > 20:
            flash += 1.0

    # Frame-based toggling: frame%N in per-frame code or shaders.
    # In shaders, frame%N directly controls color channel flipping per-frame.
    # In per-frame code, it controls rendering parameters.
    # NOT checked in wave/shape per-point code where % is used for mirroring.
    pf_and_sh = pf + "\n" + sh
    if re.search(r"frame\s*%\s*\d+", pf_and_sh):
        flash += 3.0
    elif re.search(r"(time)\s*%\s*[12]\b", pf):
        flash += 3.0

    # bnot(frame%N) — frame-skipping (e.g. only compute every Nth frame)
    if re.search(r"bnot\s*\(\s*frame\s*%", pf):
        flash += 2.0

    # equal(...%N, 0) used to control decay/zoom/brightness — periodic strobes
    # Only flag when combined with decay, zoom, or brightness controls
    if re.search(r"(decay|zoom|gamma|bright)\s*=.*equal\s*\(", pf):
        flash += 2.0
    elif re.search(r"equal\s*\(.*%\s*\d+.*\)\s*.*/(fps|frame)", pf):
        flash += 2.0

    # Binary oscillation: above(sin(... or below(sin(...
    if re.search(r"(above|below)\s*\(\s*sin\s*\(", pf):
        flash += 1.5

    # Gamma oscillation in per-frame
    if re.search(r"(gamma|fgammaadj)\s*=.*sin", pf):
        flash += 2.0

    # Decay oscillation
    if re.search(r"(decay|fdecay)\s*=.*sin", pf):
        flash += 1.5

    # Dynamic decay with sharp changes (e.g. decay=1-t1 where t1 jumps)
    if re.search(r"decay\s*=\s*1\s*-", pf):
        flash += 1.5

    # -- Shader flash patterns --

    # frac(ret...) — wrapping causes sudden brightness jumps
    if re.search(r"frac\s*\(\s*ret", sh):
        flash += 2.0

    # Multiple color channel inversions in shader (e.g. ret.x=1-ret.x on 2+ channels)
    # A single inversion is normal color correction; multiple suggest strobing.
    inversions = len(re.findall(r"(?:1\.?0?\s*-\s*ret\b|ret\s*=\s*1\.?0?\s*-)", sh))
    if inversions >= 2:
        flash += 2.0

    # Rapid time-based oscillation in shaders
    for m in re.finditer(r"sin\s*\(\s*time\s*\*\s*(\d+\.?\d*)", sh):
        freq = float(m.group(1))
        if freq > 10:
            flash += 2.0
        elif freq > 5:
            flash += 1.0

    # step/floor(time*N) with high frequency in shaders
    for m in re.finditer(r"(?:step|floor)\s*\(\s*time\s*\*\s*(\d+\.?\d*)", sh):
        if float(m.group(1)) > 3:
            flash += 2.0

    # frac(time*N) with high frequency — strobe
    for m in re.finditer(r"frac\s*\(\s*time\s*\*\s*(\d+\.?\d*)", sh):
        if float(m.group(1)) > 3:
            flash += 2.0

    # pow(-1, ...) — sign flipping
    if re.search(r"pow\s*\(\s*-1", all_code):
        flash += 1.0

    # Random color assignment per frame (e.g. r=int(rand(100))/100)
    # Multiple random color channels = strobing rainbow effect
    rand_colors = len(re.findall(r"\b[rgb]2?\s*=\s*(?:int\s*\()?\s*rand\s*\(", pf))
    if rand_colors >= 3:
        flash += 2.0

    if flash >= 2.0:
        return False

    return True


def main():
    presets_dir = sys.argv[1]
    removed = 0
    kept = 0

    for root, _dirs, files in os.walk(presets_dir):
        for fname in files:
            if not fname.endswith(".milk"):
                continue
            path = os.path.join(root, fname)
            if is_preset_safe(path):
                kept += 1
            else:
                os.remove(path)
                removed += 1

    # Clean up empty directories
    for root, dirs, files in os.walk(presets_dir, topdown=False):
        for d in dirs:
            dp = os.path.join(root, d)
            if not os.listdir(dp):
                os.rmdir(dp)

    print(f"Presets: kept {kept}, removed {removed} (bright/flashing)")


if __name__ == "__main__":
    main()
