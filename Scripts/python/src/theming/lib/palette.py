"""
Palette extraction using K-means clustering.

This module provides functions for extracting dominant colors from images
using perceptual color distance calculations and k-means clustering.
"""

import math

from .color import Color, rgb_to_hsl, hsl_to_rgb, hue_distance, rgb_to_lab, lab_to_rgb, lab_distance
from .hct import Cam16, Hct

# Type aliases
RGB = tuple[int, int, int]
HSL = tuple[float, float, float]
LAB = tuple[float, float, float]


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


def kmeans_cluster(
    colors: list[RGB],
    k: int = 5,
    iterations: int = 10
) -> list[tuple[RGB, RGB, int]]:
    """
    Perform K-means clustering on colors in Lab color space.

    Lab space is perceptually uniform, matching matugen's approach.
    Returns list of (centroid_rgb, representative_rgb, cluster_size) tuples,
    sorted by cluster size.

    - centroid_rgb: averaged color from the cluster (smoother, blended)
    - representative_rgb: actual image pixel closest to centroid
    """
    if len(colors) < k:
        # Not enough colors, return what we have (same color for centroid and representative)
        unique = list(set(colors))
        return [(c, c, colors.count(c)) for c in unique[:k]]

    # Convert to Lab for perceptual clustering (like matugen's WSMeans)
    colors_lab = [rgb_to_lab(*c) for c in colors]

    # Deterministic initialization: pick evenly spaced colors from sorted list
    # Sort by L (lightness) first for better spread
    sorted_indices = sorted(range(len(colors_lab)), key=lambda i: colors_lab[i][0])
    step = len(sorted_indices) // k
    centroids = [colors_lab[sorted_indices[i * step]] for i in range(k)]

    # K-means iterations
    assignments = [0] * len(colors_lab)
    for _ in range(iterations):
        # Assign colors to nearest centroid
        for idx, color in enumerate(colors_lab):
            min_dist = float('inf')
            min_cluster = 0
            for i, centroid in enumerate(centroids):
                dist = lab_distance(color, centroid)
                if dist < min_dist:
                    min_dist = dist
                    min_cluster = i
            assignments[idx] = min_cluster

        # Update centroids (simple mean in Lab space)
        new_centroids = []
        for i in range(k):
            cluster_colors = [colors_lab[j] for j in range(len(colors_lab)) if assignments[j] == i]
            if cluster_colors:
                avg_L = sum(c[0] for c in cluster_colors) / len(cluster_colors)
                avg_a = sum(c[1] for c in cluster_colors) / len(cluster_colors)
                avg_b = sum(c[2] for c in cluster_colors) / len(cluster_colors)
                new_centroids.append((avg_L, avg_a, avg_b))
            else:
                new_centroids.append(centroids[i])

        centroids = new_centroids

    # Final assignment and count, also find representative pixel (closest to centroid)
    cluster_counts = [0] * k
    cluster_representatives: list[tuple[RGB, float]] = [(colors[0], float('inf'))] * k

    for idx, color_lab in enumerate(colors_lab):
        cluster_idx = assignments[idx]
        cluster_counts[cluster_idx] += 1

        # Track the pixel closest to the centroid as the representative
        dist = lab_distance(color_lab, centroids[cluster_idx])
        if dist < cluster_representatives[cluster_idx][1]:
            cluster_representatives[cluster_idx] = (colors[idx], dist)

    # Return both centroid (averaged) and representative (actual pixel) colors
    results = []
    for i in range(k):
        if cluster_counts[i] > 0:
            # Convert Lab centroid back to RGB
            centroid_rgb = lab_to_rgb(*centroids[i])
            representative_rgb = cluster_representatives[i][0]
            results.append((centroid_rgb, representative_rgb, cluster_counts[i]))

    # Sort by cluster size (most common first)
    results.sort(key=lambda x: -x[2])

    return results


def _score_colors_chroma(
    colors_with_counts: list[tuple[RGB, int]],
) -> list[tuple[Color, float]]:
    """
    Score colors prioritizing chroma (vibrancy) over area coverage.

    Uses count^0.3 weighting so saturated colors win even with small area.
    Used for "vibrant" mode to find the most eye-catching colors.

    Args:
        colors_with_counts: List of (RGB, count) tuples from clustering

    Returns:
        List of (Color, score) tuples, sorted by score descending
    """
    result_colors = []
    for rgb, count in colors_with_counts:
        color = Color.from_rgb(rgb)
        try:
            hct = color.to_hct()

            # Chroma contribution - prefer colorful colors
            chroma_score = hct.chroma

            # Tone penalty - prefer mid-tones (40-60 is ideal)
            if hct.tone < 20:
                tone_penalty = (20 - hct.tone) * 2
            elif hct.tone > 80:
                tone_penalty = (hct.tone - 80) * 1.5
            elif hct.tone < 40:
                tone_penalty = (40 - hct.tone) * 0.5
            elif hct.tone > 60:
                tone_penalty = (hct.tone - 60) * 0.3
            else:
                tone_penalty = 0

            # Hue penalty - slight penalty for yellow-green hues
            if 80 < hct.hue < 110:
                hue_penalty = 5
            else:
                hue_penalty = 0

            # Combined score: chroma minus penalties, balanced with count
            # Using count^0.3 so chroma dominates while still considering area
            score = (chroma_score - tone_penalty - hue_penalty) * (count ** 0.3)
            result_colors.append((color, score))
        except (ValueError, ZeroDivisionError):
            result_colors.append((color, 0.0))

    result_colors.sort(key=lambda x: -x[1])
    return result_colors


def _hue_to_family(hue: float) -> int:
    """
    Map hue to perceptual color family.

    Uses non-uniform ranges that match human color perception:
    - 0: RED (330-30°, wraps around)
    - 1: ORANGE (30-60°)
    - 2: YELLOW (60-105°)
    - 3: GREEN (105-190°, includes green-leaning teal)
    - 4: BLUE (190-270°, includes cyan)
    - 5: PURPLE (270-330°)
    """
    if hue >= 330 or hue < 30:
        return 0  # RED
    elif hue < 60:
        return 1  # ORANGE
    elif hue < 105:
        return 2  # YELLOW
    elif hue < 190:
        return 3  # GREEN (includes green-leaning teal)
    elif hue < 270:
        return 4  # BLUE (includes cyan)
    else:
        return 5  # PURPLE


def _score_colors_count(
    colors_with_counts: list[tuple[RGB, int]],
) -> list[tuple[Color, float]]:
    """
    Score colors prioritizing pixel count (area coverage) by hue family.

    Groups colors into perceptual hue families, sums counts per family,
    then picks the dominant family. This is more faithful to human perception
    where we see "green" as a category, not individual shades.

    Args:
        colors_with_counts: List of (RGB, count) tuples from clustering

    Returns:
        List of (Color, score) tuples, sorted by family dominance then count
    """
    MIN_CHROMA = 10.0  # Filter out near-gray colors

    # First pass: collect colorful colors and group by hue family
    hue_families: dict[int, list[tuple[Color, float, float, int]]] = {}  # family -> [(color, hue, chroma, count), ...]

    for rgb, count in colors_with_counts:
        color = Color.from_rgb(rgb)
        try:
            hct = color.to_hct()
            if hct.chroma >= MIN_CHROMA:
                family = _hue_to_family(hct.hue)
                if family not in hue_families:
                    hue_families[family] = []
                hue_families[family].append((color, hct.hue, hct.chroma, count))
        except (ValueError, ZeroDivisionError):
            pass

    # If no colorful colors found, fall back to all colors
    if not hue_families:
        result = []
        for rgb, count in colors_with_counts:
            color = Color.from_rgb(rgb)
            result.append((color, float(count)))
        result.sort(key=lambda x: -x[1])
        return result

    # Calculate total count per hue family
    family_totals: list[tuple[int, int]] = []
    for family, colors in hue_families.items():
        total = sum(c[3] for c in colors)
        family_totals.append((family, total))

    # Sort families by total count (dominant family first)
    family_totals.sort(key=lambda x: -x[1])

    # Build result: colors from dominant families first, sorted by count within each family
    result_colors = []
    for family, _ in family_totals:
        family_colors = hue_families[family]
        # Sort by count descending, chroma as tiebreaker
        family_colors.sort(key=lambda x: (-x[3], -x[2]))
        for color, hue, chroma, count in family_colors:
            # Score encodes family rank + count for proper ordering
            family_rank = next(i for i, (f, _) in enumerate(family_totals) if f == family)
            score = (len(family_totals) - family_rank) * 1000000 + count * 1000 + chroma
            result_colors.append((color, score))

    result_colors.sort(key=lambda x: -x[1])
    return result_colors


def _family_center_hue(family: int) -> float:
    """Get the center hue for a family index."""
    # Family centers based on _hue_to_family ranges:
    # 0: RED (330-30°, wraps) -> center 0°
    # 1: ORANGE (30-60°) -> center 45°
    # 2: YELLOW (60-105°) -> center 82.5°
    # 3: GREEN (105-190°) -> center 147.5°
    # 4: BLUE (190-270°) -> center 230°
    # 5: PURPLE (270-330°) -> center 300°
    centers = [0.0, 45.0, 82.5, 147.5, 230.0, 300.0]
    return centers[family]


def _circular_hue_diff(h1: float, h2: float) -> float:
    """Calculate circular hue difference (0-180)."""
    diff = abs(h1 - h2)
    return min(diff, 360.0 - diff)


def _score_colors_dysfunctional(
    colors_with_counts: list[tuple[RGB, int]],
) -> list[tuple[Color, float]]:
    """
    Score colors prioritizing the 2nd most dominant hue family.

    Like count scoring but skips the dominant family (and any families
    too close to it) to pick a visually distinct secondary color.

    Args:
        colors_with_counts: List of (RGB, count) tuples from clustering

    Returns:
        List of (Color, score) tuples, sorted by family dominance then count
    """
    MIN_CHROMA = 10.0  # Filter out near-gray colors
    MIN_HUE_DISTANCE = 45.0  # Minimum hue distance from dominant family
    MIN_COUNT_RATIO = 0.02  # Distant family must have at least 2% of total colorful pixels

    # First pass: collect colorful colors and group by hue family
    hue_families: dict[int, list[tuple[Color, float, float, int]]] = {}  # family -> [(color, hue, chroma, count), ...]

    for rgb, count in colors_with_counts:
        color = Color.from_rgb(rgb)
        try:
            hct = color.to_hct()
            if hct.chroma >= MIN_CHROMA:
                family = _hue_to_family(hct.hue)
                if family not in hue_families:
                    hue_families[family] = []
                hue_families[family].append((color, hct.hue, hct.chroma, count))
        except (ValueError, ZeroDivisionError):
            pass

    # If no colorful colors found, fall back to all colors
    if not hue_families:
        result = []
        for rgb, count in colors_with_counts:
            color = Color.from_rgb(rgb)
            result.append((color, float(count)))
        result.sort(key=lambda x: -x[1])
        return result

    # Calculate total count per hue family
    family_totals: list[tuple[int, int]] = []
    for family, colors in hue_families.items():
        total = sum(c[3] for c in colors)
        family_totals.append((family, total))

    # Sort families by total count (dominant family first)
    family_totals.sort(key=lambda x: -x[1])

    # Find the dominant family and its center hue
    dominant_family, dominant_count = family_totals[0]
    dominant_center = _family_center_hue(dominant_family)
    total_colorful_pixels = sum(count for _, count in family_totals)
    min_count = total_colorful_pixels * MIN_COUNT_RATIO

    # Find families that are far enough from the dominant one AND have enough pixels
    distant_families = []
    close_families = [dominant_family]
    for family, count in family_totals[1:]:
        family_center = _family_center_hue(family)
        hue_diff = _circular_hue_diff(dominant_center, family_center)
        if hue_diff >= MIN_HUE_DISTANCE and count >= min_count:
            # Get max chroma in this family - we want families with vibrant colors
            max_chroma = max(c[2] for c in hue_families[family])
            distant_families.append((family, count, hue_diff, max_chroma))
        else:
            close_families.append(family)

    # Build result: colors from distant families first
    result_colors = []

    # Sort distant families by weighted score: hue_distance * max_chroma
    # This balances visual distinctness (hue distance) with color quality (chroma)
    # A family that's far away AND has good colors beats one that's close with great colors
    distant_families.sort(key=lambda x: -(x[2] * x[3]))

    for family, _, _, _ in distant_families:
        family_colors = hue_families[family]
        # Sort by chroma descending - we want the most vibrant color from this family
        # Count is tiebreaker to avoid picking tiny noise clusters
        family_colors.sort(key=lambda x: (-x[2], -x[3]))
        for color, hue, chroma, count in family_colors:
            # Score encodes family rank + chroma for proper ordering
            # Chroma is primary (we want vibrant), count is tiebreaker
            family_rank = next(i for i, (f, _, _, _) in enumerate(distant_families) if f == family)
            score = (len(distant_families) - family_rank) * 1000000 + chroma * 1000 + count
            result_colors.append((color, score))

    # Add colors from close families (including dominant) at lower priority
    for family in close_families:
        family_colors = hue_families[family]
        family_colors.sort(key=lambda x: (-x[3], -x[2]))
        for color, hue, chroma, count in family_colors:
            # Lower score than all distant-family colors
            score = count * 1000 + chroma
            result_colors.append((color, score))

    result_colors.sort(key=lambda x: -x[1])
    return result_colors


def _score_colors_muted(
    colors_with_counts: list[tuple[RGB, int]],
) -> list[tuple[Color, float]]:
    """
    Score colors for muted mode - pure pixel count without chroma filtering.

    Unlike count scoring which filters to chroma >= 10, this accepts all colors
    including grayscale. Designed for monochrome/monotonal wallpapers where
    the dominant color may have very low or zero saturation.

    Args:
        colors_with_counts: List of (RGB, count) tuples from clustering

    Returns:
        List of (Color, score) tuples, sorted by count descending
    """
    result = []
    for rgb, count in colors_with_counts:
        color = Color.from_rgb(rgb)
        result.append((color, float(count)))

    result.sort(key=lambda x: -x[1])
    return result


def _score_colors_population(
    colors_with_counts: list[tuple[RGB, int]],
    total_pixels: int
) -> list[tuple[Color, float]]:
    """
    Score colors using Material Design's Score algorithm.

    This matches matugen's scoring approach exactly:
    - Build per-hue population histogram (360 buckets)
    - Calculate "excited proportions" (±15° hue window sum)
    - Score: proportion * 100 * 0.7 + (chroma - 48) * weight
    - Filter by chroma >= 5 and proportion >= 1%
    - Deduplicate by maximizing hue distance

    Args:
        colors_with_counts: List of (RGB, count) tuples from clustering
        total_pixels: Total number of pixels in the sample

    Returns:
        List of (Color, score) tuples, sorted by score descending
    """
    # Constants matching Material Score
    TARGET_CHROMA = 48.0
    WEIGHT_PROPORTION = 0.7
    WEIGHT_CHROMA_ABOVE = 0.3
    WEIGHT_CHROMA_BELOW = 0.1
    CUTOFF_CHROMA = 5.0
    CUTOFF_EXCITED_PROPORTION = 0.01

    # Build per-hue population histogram (360 buckets)
    hue_population = [0] * 360
    population_sum = 0

    colors_hct: list[tuple[Color, Hct, int]] = []
    for rgb, count in colors_with_counts:
        try:
            color = Color.from_rgb(rgb)
            hct = color.to_hct()
            hue_bucket = int(hct.hue) % 360
            hue_population[hue_bucket] += count
            population_sum += count
            colors_hct.append((color, hct, count))
        except (ValueError, ZeroDivisionError):
            continue

    if not colors_hct or population_sum == 0:
        # Fallback: return colors without scoring
        result = []
        for rgb, count in colors_with_counts:
            color = Color.from_rgb(rgb)
            result.append((color, float(count)))
        return sorted(result, key=lambda x: -x[1])

    # Calculate "excited proportions" - sum of proportions in ±15° hue window
    hue_excited_proportions = [0.0] * 360
    for hue in range(360):
        proportion = hue_population[hue] / population_sum
        # Spread to neighboring hues (±15°, so 30° total window)
        for offset in range(-14, 16):
            neighbor_hue = (hue + offset) % 360
            hue_excited_proportions[neighbor_hue] += proportion

    # Score each color
    scored_hcts: list[tuple[Color, Hct, float]] = []
    for color, hct, count in colors_hct:
        hue_bucket = int(hct.hue) % 360
        proportion = hue_excited_proportions[hue_bucket]

        # Filter by chroma and proportion
        if hct.chroma < CUTOFF_CHROMA:
            continue
        if proportion <= CUTOFF_EXCITED_PROPORTION:
            continue

        # Proportion score (70% weight)
        proportion_score = proportion * 100.0 * WEIGHT_PROPORTION

        # Chroma score: (chroma - target) * weight
        # This gives bonus for high chroma, penalty for low chroma
        if hct.chroma < TARGET_CHROMA:
            chroma_weight = WEIGHT_CHROMA_BELOW
        else:
            chroma_weight = WEIGHT_CHROMA_ABOVE
        chroma_score = (hct.chroma - TARGET_CHROMA) * chroma_weight

        score = proportion_score + chroma_score
        scored_hcts.append((color, hct, score))

    if not scored_hcts:
        # Fallback if filtering removed everything
        result = []
        for rgb, count in colors_with_counts:
            color = Color.from_rgb(rgb)
            result.append((color, float(count)))
        return sorted(result, key=lambda x: -x[1])

    # Sort by score descending
    scored_hcts.sort(key=lambda x: -x[2])

    # Deduplicate by hue distance - pick colors maximizing hue diversity
    # Start at 90° minimum distance, decrease to 15° if needed
    chosen_colors: list[tuple[Color, float]] = []

    for min_hue_diff in range(90, 14, -1):
        chosen_colors.clear()
        for color, hct, score in scored_hcts:
            # Check if this hue is far enough from all chosen colors
            is_far_enough = True
            for chosen_color, _ in chosen_colors:
                chosen_hct = chosen_color.to_hct()
                if hue_distance(hct.hue, chosen_hct.hue) < min_hue_diff:
                    is_far_enough = False
                    break

            if is_far_enough:
                chosen_colors.append((color, score))

            # Stop if we have enough colors (4 is Material default)
            if len(chosen_colors) >= 4:
                break

        # If we found enough colors, stop decreasing threshold
        if len(chosen_colors) >= 4:
            break

    # If deduplication yielded nothing, fall back to top scored
    if not chosen_colors:
        chosen_colors = [(c, s) for c, h, s in scored_hcts[:4]]

    return chosen_colors


def extract_palette(
    pixels: list[RGB],
    k: int = 5,
    scoring: str = "population"
) -> list[Color]:
    """
    Extract K dominant colors from pixel data.

    Args:
        pixels: List of RGB tuples
        k: Number of colors to extract
        scoring: Scoring method:
                 - "population": matugen-like, representative colors (M3 schemes)
                 - "chroma": vibrant, chroma-prioritized with centroid averaging
                 - "count": area-dominant, picks by pixel count (faithful mode)
                 - "dysfunctional": picks 2nd most dominant color family
                 - "muted": like count but without chroma filtering (monochrome wallpapers)

    Returns:
        List of Color objects, sorted by score
    """
    # Downsample for performance
    sampled = downsample_pixels(pixels, factor=4)
    total_sampled = len(sampled)

    # For population scoring, we need many clusters then score/filter them
    # For chroma scoring, fewer clusters work fine
    if scoring == "population":
        # Use more clusters for Material scoring (like matugen's 128-256)
        cluster_count = min(128, max(k * 10, len(set(sampled)) // 10))
        # Don't pre-filter for population scoring - let the Score algorithm filter
        # This matches matugen which quantizes all pixels, then filters in scoring
        filtered = sampled
    elif scoring == "count":
        # Faithful mode: many clusters to capture color diversity, no pre-filtering
        # Scoring will filter to colorful colors and pick by count
        cluster_count = 48
        filtered = sampled
    elif scoring == "dysfunctional":
        # Dysfunctional mode: same as count but picks 2nd dominant family
        cluster_count = 48
        filtered = sampled
    elif scoring == "muted":
        # Muted mode: similar to count but accepts low-chroma colors
        # For monochrome/monotonal wallpapers
        cluster_count = 24
        filtered = sampled
    else:
        # Vibrant mode: more clusters to capture high-chroma colors that might
        # otherwise get averaged away, with colorfulness pre-filter
        cluster_count = 20
        # Filter to colorful pixels for smoother averaged results
        filtered = []
        for p in sampled:
            try:
                cam = Cam16.from_rgb(p[0], p[1], p[2])
                if cam.chroma >= 5.0:
                    filtered.append(p)
            except (ValueError, ZeroDivisionError):
                continue

        if len(filtered) < cluster_count * 2:
            filtered = sampled

    # Cluster - returns (centroid_rgb, representative_rgb, count) tuples
    clusters = kmeans_cluster(filtered, k=cluster_count)

    # Score colors based on method
    # - chroma: centroid colors (averaged, smoother - vibrant mode)
    # - count: representative pixels by area dominance (faithful mode)
    # - muted: like count but accepts low/zero chroma (monochrome wallpapers)
    # - population: representative colors with Material scoring (M3 schemes)
    if scoring == "chroma":
        # Use centroid colors for vibrant mode (smoother, blended)
        colors_for_scoring = [(c[0], c[2]) for c in clusters]
        scored = _score_colors_chroma(colors_for_scoring)
    elif scoring == "count":
        # Use representative colors with count scoring (faithful mode)
        colors_for_scoring = [(c[1], c[2]) for c in clusters]
        scored = _score_colors_count(colors_for_scoring)
    elif scoring == "dysfunctional":
        # Use representative colors with dysfunctional scoring (2nd dominant family)
        colors_for_scoring = [(c[1], c[2]) for c in clusters]
        scored = _score_colors_dysfunctional(colors_for_scoring)
    elif scoring == "muted":
        # Use representative colors with muted scoring (no chroma filter)
        colors_for_scoring = [(c[1], c[2]) for c in clusters]
        scored = _score_colors_muted(colors_for_scoring)
    else:
        # Use representative colors for M3 schemes
        colors_for_scoring = [(c[1], c[2]) for c in clusters]
        scored = _score_colors_population(colors_for_scoring, total_sampled)

    # Extract colors
    final_colors = [c[0] for c in scored]

    # Ensure we have enough colors by deriving from primary using HCT
    while len(final_colors) < k:
        if not final_colors:
            final_colors.append(Color.from_hex("#6750A4"))
            continue

        primary = final_colors[0]
        primary_hct = primary.to_hct()
        offset = len(final_colors) * 60.0
        new_hct = Hct((primary_hct.hue + offset) % 360.0, primary_hct.chroma, primary_hct.tone)
        final_colors.append(Color.from_hct(new_hct))

    return final_colors[:k]


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


