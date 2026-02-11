"""
Wu and WSMeans quantizer implementations matching material-color-utilities.

Wu implements Xiaolin Wu's color quantization algorithm from Graphics Gems II (1991).
WSMeans refines Wu's output via weighted k-means in Lab space (QuantizerCelebi pipeline).
Together they match the QuantizerCelebi pipeline used by matugen/material-color-utilities.
"""

from typing import Dict, List, Tuple

from .color import rgb_to_lab, lab_to_rgb

# Constants matching material-color-utilities
INDEX_BITS = 5
SIDE_LENGTH = 33  # (1 << INDEX_BITS) + 1
TOTAL_SIZE = 35937  # SIDE_LENGTH^3

# Direction constants
DIR_RED = 0
DIR_GREEN = 1
DIR_BLUE = 2


class Box:
    """Represents a box in RGB color space."""
    __slots__ = ('r0', 'r1', 'g0', 'g1', 'b0', 'b1', 'vol')

    def __init__(self):
        self.r0 = 0
        self.r1 = 0
        self.g0 = 0
        self.g1 = 0
        self.b0 = 0
        self.b1 = 0
        self.vol = 0


def _get_index(r: int, g: int, b: int) -> int:
    """Calculate 3D array index from RGB coordinates."""
    return (r << (INDEX_BITS * 2)) + (r << (INDEX_BITS + 1)) + r + (g << INDEX_BITS) + g + b


def _argb_from_rgb(r: int, g: int, b: int) -> int:
    """Convert RGB to ARGB integer format."""
    return (255 << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF)


def _rgb_from_argb(argb: int) -> Tuple[int, int, int]:
    """Extract RGB from ARGB integer."""
    return ((argb >> 16) & 0xFF, (argb >> 8) & 0xFF, argb & 0xFF)


class QuantizerWu:
    """
    Wu color quantizer implementation.

    Divides image pixels into clusters by recursively cutting an RGB cube,
    based on the weight of pixels in each area of the cube.
    """

    def __init__(self):
        self.weights: List[int] = []
        self.moments_r: List[int] = []
        self.moments_g: List[int] = []
        self.moments_b: List[int] = []
        self.moments: List[float] = []
        self.cubes: List[Box] = []

    def quantize(self, pixels: List[int], max_colors: int) -> List[int]:
        """
        Quantize pixels to a reduced color palette.

        Args:
            pixels: List of colors in ARGB integer format
            max_colors: Maximum number of colors to return

        Returns:
            List of colors in ARGB format
        """
        self._construct_histogram(pixels)
        self._compute_moments()
        result_count = self._create_boxes(max_colors)
        return self._create_result(result_count)

    def _construct_histogram(self, pixels: List[int]):
        """Build histogram of pixel colors."""
        self.weights = [0] * TOTAL_SIZE
        self.moments_r = [0] * TOTAL_SIZE
        self.moments_g = [0] * TOTAL_SIZE
        self.moments_b = [0] * TOTAL_SIZE
        self.moments = [0.0] * TOTAL_SIZE

        # Count pixels by color
        count_by_color: Dict[int, int] = {}
        for pixel in pixels:
            # Only count fully opaque pixels
            if (pixel >> 24) & 0xFF == 255:
                count_by_color[pixel] = count_by_color.get(pixel, 0) + 1

        bits_to_remove = 8 - INDEX_BITS
        for pixel, count in count_by_color.items():
            red = (pixel >> 16) & 0xFF
            green = (pixel >> 8) & 0xFF
            blue = pixel & 0xFF

            i_r = (red >> bits_to_remove) + 1
            i_g = (green >> bits_to_remove) + 1
            i_b = (blue >> bits_to_remove) + 1
            index = _get_index(i_r, i_g, i_b)

            self.weights[index] += count
            self.moments_r[index] += count * red
            self.moments_g[index] += count * green
            self.moments_b[index] += count * blue
            self.moments[index] += count * (red * red + green * green + blue * blue)

    def _compute_moments(self):
        """Compute cumulative moments for efficient volume calculations."""
        for r in range(1, SIDE_LENGTH):
            area = [0] * SIDE_LENGTH
            area_r = [0] * SIDE_LENGTH
            area_g = [0] * SIDE_LENGTH
            area_b = [0] * SIDE_LENGTH
            area2 = [0.0] * SIDE_LENGTH

            for g in range(1, SIDE_LENGTH):
                line = 0
                line_r = 0
                line_g = 0
                line_b = 0
                line2 = 0.0

                for b in range(1, SIDE_LENGTH):
                    index = _get_index(r, g, b)
                    line += self.weights[index]
                    line_r += self.moments_r[index]
                    line_g += self.moments_g[index]
                    line_b += self.moments_b[index]
                    line2 += self.moments[index]

                    area[b] += line
                    area_r[b] += line_r
                    area_g[b] += line_g
                    area_b[b] += line_b
                    area2[b] += line2

                    prev_index = _get_index(r - 1, g, b)
                    self.weights[index] = self.weights[prev_index] + area[b]
                    self.moments_r[index] = self.moments_r[prev_index] + area_r[b]
                    self.moments_g[index] = self.moments_g[prev_index] + area_g[b]
                    self.moments_b[index] = self.moments_b[prev_index] + area_b[b]
                    self.moments[index] = self.moments[prev_index] + area2[b]

    def _create_boxes(self, max_colors: int) -> int:
        """Create color boxes by recursive cutting."""
        self.cubes = [Box() for _ in range(max_colors)]
        volume_variance = [0.0] * max_colors

        # Initialize first box to cover entire color space
        self.cubes[0].r1 = SIDE_LENGTH - 1
        self.cubes[0].g1 = SIDE_LENGTH - 1
        self.cubes[0].b1 = SIDE_LENGTH - 1

        generated_color_count = max_colors
        next_box = 0
        i = 1

        while i < max_colors:
            if self._cut(self.cubes[next_box], self.cubes[i]):
                volume_variance[next_box] = (
                    self._variance(self.cubes[next_box])
                    if self.cubes[next_box].vol > 1 else 0.0
                )
                volume_variance[i] = (
                    self._variance(self.cubes[i])
                    if self.cubes[i].vol > 1 else 0.0
                )
            else:
                volume_variance[next_box] = 0.0
                i -= 1

            # Find box with maximum variance
            next_box = 0
            temp = volume_variance[0]
            for j in range(1, i + 1):
                if volume_variance[j] > temp:
                    temp = volume_variance[j]
                    next_box = j

            if temp <= 0.0:
                generated_color_count = i + 1
                break

            i += 1

        return generated_color_count

    def _create_result(self, color_count: int) -> List[int]:
        """Extract final colors from boxes."""
        colors = []
        for i in range(color_count):
            cube = self.cubes[i]
            weight = self._volume(cube, self.weights)
            if weight > 0:
                r = int(self._volume(cube, self.moments_r) / weight)
                g = int(self._volume(cube, self.moments_g) / weight)
                b = int(self._volume(cube, self.moments_b) / weight)
                color = _argb_from_rgb(r, g, b)
                colors.append(color)
        return colors

    def _variance(self, cube: Box) -> float:
        """Calculate variance within a box."""
        dr = self._volume(cube, self.moments_r)
        dg = self._volume(cube, self.moments_g)
        db = self._volume(cube, self.moments_b)

        xx = (
            self.moments[_get_index(cube.r1, cube.g1, cube.b1)]
            - self.moments[_get_index(cube.r1, cube.g1, cube.b0)]
            - self.moments[_get_index(cube.r1, cube.g0, cube.b1)]
            + self.moments[_get_index(cube.r1, cube.g0, cube.b0)]
            - self.moments[_get_index(cube.r0, cube.g1, cube.b1)]
            + self.moments[_get_index(cube.r0, cube.g1, cube.b0)]
            + self.moments[_get_index(cube.r0, cube.g0, cube.b1)]
            - self.moments[_get_index(cube.r0, cube.g0, cube.b0)]
        )

        hypotenuse = dr * dr + dg * dg + db * db
        volume = self._volume(cube, self.weights)
        if volume == 0:
            return 0.0
        return xx - hypotenuse / volume

    def _cut(self, one: Box, two: Box) -> bool:
        """Cut a box into two boxes along the optimal axis."""
        whole_r = self._volume(one, self.moments_r)
        whole_g = self._volume(one, self.moments_g)
        whole_b = self._volume(one, self.moments_b)
        whole_w = self._volume(one, self.weights)

        max_r_cut, max_r = self._maximize(
            one, DIR_RED, one.r0 + 1, one.r1, whole_r, whole_g, whole_b, whole_w
        )
        max_g_cut, max_g = self._maximize(
            one, DIR_GREEN, one.g0 + 1, one.g1, whole_r, whole_g, whole_b, whole_w
        )
        max_b_cut, max_b = self._maximize(
            one, DIR_BLUE, one.b0 + 1, one.b1, whole_r, whole_g, whole_b, whole_w
        )

        if max_r >= max_g and max_r >= max_b:
            if max_r_cut < 0:
                return False
            direction = DIR_RED
            cut_location = max_r_cut
        elif max_g >= max_r and max_g >= max_b:
            direction = DIR_GREEN
            cut_location = max_g_cut
        else:
            direction = DIR_BLUE
            cut_location = max_b_cut

        two.r1 = one.r1
        two.g1 = one.g1
        two.b1 = one.b1

        if direction == DIR_RED:
            one.r1 = cut_location
            two.r0 = one.r1
            two.g0 = one.g0
            two.b0 = one.b0
        elif direction == DIR_GREEN:
            one.g1 = cut_location
            two.r0 = one.r0
            two.g0 = one.g1
            two.b0 = one.b0
        else:  # DIR_BLUE
            one.b1 = cut_location
            two.r0 = one.r0
            two.g0 = one.g0
            two.b0 = one.b1

        one.vol = (one.r1 - one.r0) * (one.g1 - one.g0) * (one.b1 - one.b0)
        two.vol = (two.r1 - two.r0) * (two.g1 - two.g0) * (two.b1 - two.b0)
        return True

    def _maximize(
        self,
        cube: Box,
        direction: int,
        first: int,
        last: int,
        whole_r: int,
        whole_g: int,
        whole_b: int,
        whole_w: int,
    ) -> Tuple[int, float]:
        """Find the optimal cut position along an axis."""
        bottom_r = self._bottom(cube, direction, self.moments_r)
        bottom_g = self._bottom(cube, direction, self.moments_g)
        bottom_b = self._bottom(cube, direction, self.moments_b)
        bottom_w = self._bottom(cube, direction, self.weights)

        max_val = 0.0
        cut = -1

        for i in range(first, last):
            half_r = bottom_r + self._top(cube, direction, i, self.moments_r)
            half_g = bottom_g + self._top(cube, direction, i, self.moments_g)
            half_b = bottom_b + self._top(cube, direction, i, self.moments_b)
            half_w = bottom_w + self._top(cube, direction, i, self.weights)

            if half_w == 0:
                continue

            temp = (half_r * half_r + half_g * half_g + half_b * half_b) / half_w

            half_r = whole_r - half_r
            half_g = whole_g - half_g
            half_b = whole_b - half_b
            half_w = whole_w - half_w

            if half_w == 0:
                continue

            temp += (half_r * half_r + half_g * half_g + half_b * half_b) / half_w

            if temp > max_val:
                max_val = temp
                cut = i

        return cut, max_val

    def _volume(self, cube: Box, moment: List) -> int:
        """Calculate volume sum using inclusion-exclusion."""
        return (
            moment[_get_index(cube.r1, cube.g1, cube.b1)]
            - moment[_get_index(cube.r1, cube.g1, cube.b0)]
            - moment[_get_index(cube.r1, cube.g0, cube.b1)]
            + moment[_get_index(cube.r1, cube.g0, cube.b0)]
            - moment[_get_index(cube.r0, cube.g1, cube.b1)]
            + moment[_get_index(cube.r0, cube.g1, cube.b0)]
            + moment[_get_index(cube.r0, cube.g0, cube.b1)]
            - moment[_get_index(cube.r0, cube.g0, cube.b0)]
        )

    def _bottom(self, cube: Box, direction: int, moment: List) -> int:
        """Calculate bottom sum for maximize."""
        if direction == DIR_RED:
            return (
                -moment[_get_index(cube.r0, cube.g1, cube.b1)]
                + moment[_get_index(cube.r0, cube.g1, cube.b0)]
                + moment[_get_index(cube.r0, cube.g0, cube.b1)]
                - moment[_get_index(cube.r0, cube.g0, cube.b0)]
            )
        elif direction == DIR_GREEN:
            return (
                -moment[_get_index(cube.r1, cube.g0, cube.b1)]
                + moment[_get_index(cube.r1, cube.g0, cube.b0)]
                + moment[_get_index(cube.r0, cube.g0, cube.b1)]
                - moment[_get_index(cube.r0, cube.g0, cube.b0)]
            )
        else:  # DIR_BLUE
            return (
                -moment[_get_index(cube.r1, cube.g1, cube.b0)]
                + moment[_get_index(cube.r1, cube.g0, cube.b0)]
                + moment[_get_index(cube.r0, cube.g1, cube.b0)]
                - moment[_get_index(cube.r0, cube.g0, cube.b0)]
            )

    def _top(self, cube: Box, direction: int, position: int, moment: List) -> int:
        """Calculate top sum for maximize."""
        if direction == DIR_RED:
            return (
                moment[_get_index(position, cube.g1, cube.b1)]
                - moment[_get_index(position, cube.g1, cube.b0)]
                - moment[_get_index(position, cube.g0, cube.b1)]
                + moment[_get_index(position, cube.g0, cube.b0)]
            )
        elif direction == DIR_GREEN:
            return (
                moment[_get_index(cube.r1, position, cube.b1)]
                - moment[_get_index(cube.r1, position, cube.b0)]
                - moment[_get_index(cube.r0, position, cube.b1)]
                + moment[_get_index(cube.r0, position, cube.b0)]
            )
        else:  # DIR_BLUE
            return (
                moment[_get_index(cube.r1, cube.g1, position)]
                - moment[_get_index(cube.r1, cube.g0, position)]
                - moment[_get_index(cube.r0, cube.g1, position)]
                + moment[_get_index(cube.r0, cube.g0, position)]
            )


def quantize_wu(pixels: List[Tuple[int, int, int]], max_colors: int = 128) -> Dict[int, int]:
    """
    Quantize RGB pixels using Wu algorithm.

    Args:
        pixels: List of (R, G, B) tuples
        max_colors: Maximum colors to extract

    Returns:
        Dictionary mapping ARGB colors to pixel counts
    """
    # Convert RGB tuples to ARGB integers
    argb_pixels = [_argb_from_rgb(r, g, b) for r, g, b in pixels]

    # Run Wu quantizer
    quantizer = QuantizerWu()
    result_colors = quantizer.quantize(argb_pixels, max_colors)

    # Build color to count mapping in box order (matching Rust's IndexMap insertion order)
    # Wu returns colors with count 0; WSMeans uses only the keys as starting clusters
    color_to_count: Dict[int, int] = {c: 0 for c in result_colors}

    return color_to_count


# =============================================================================
# WSMeans Quantizer - weighted k-means refinement in Lab space
# =============================================================================

# Mask for 48-bit LCG state
_LCG_MASK = (1 << 48) - 1


class _Random:
    """LCG matching Java's java.util.Random / material-color-utilities."""

    def __init__(self, seed: int):
        self._seed = (seed ^ 0x5DEECE66D) & _LCG_MASK

    def _next(self, bits: int) -> int:
        self._seed = (self._seed * 0x5DEECE66D + 0xB) & _LCG_MASK
        # Unsigned right shift: treat as unsigned 48-bit, shift, return as signed 32-bit
        val = self._seed >> (48 - bits)
        # Convert to signed 32-bit int to match Java behavior
        if val >= (1 << 31):
            val -= (1 << 32)
        return val

    def next_range(self, range_val: int) -> int:
        if (range_val & -range_val) == range_val:
            # Power of 2
            return (range_val * self._next(31)) >> 31
        while True:
            bits = self._next(31)
            val = bits % range_val
            if bits - val + (range_val - 1) >= 0:
                return val


def _lab_distance_squared(a: Tuple[float, float, float], b: Tuple[float, float, float]) -> float:
    """Squared Euclidean distance in Lab space (no sqrt)."""
    dL = a[0] - b[0]
    da = a[1] - b[1]
    db = a[2] - b[2]
    return dL * dL + da * da + db * db


def quantize_wsmeans(
    pixels: List[Tuple[int, int, int]],
    max_colors: int,
    starting_clusters: List[int],
) -> Dict[int, int]:
    """
    Refine quantized colors via weighted k-means in Lab space.

    Port of QuantizerWsmeans from material-colors-0.4.2 Rust crate.

    Args:
        pixels: List of (R, G, B) tuples (original image pixels)
        max_colors: Maximum number of colors
        starting_clusters: List of ARGB colors from Wu quantizer

    Returns:
        Dictionary mapping ARGB colors to pixel counts
    """
    # Deduplicate pixels, build count map and Lab points
    pixel_to_count: Dict[int, int] = {}
    unique_pixels: List[int] = []  # ARGB values in insertion order
    points: List[Tuple[float, float, float]] = []  # Lab coordinates

    for r, g, b in pixels:
        argb = _argb_from_rgb(r, g, b)
        if argb in pixel_to_count:
            pixel_to_count[argb] += 1
        else:
            unique_pixels.append(argb)
            points.append(rgb_to_lab(r, g, b))
            pixel_to_count[argb] = 1

    cluster_count = min(max_colors, len(points))
    if cluster_count == 0:
        return {}

    # Convert starting clusters from ARGB to Lab
    clusters: List[Tuple[float, float, float]] = []
    for argb in starting_clusters:
        cr, cg, cb = _rgb_from_argb(argb)
        clusters.append(rgb_to_lab(cr, cg, cb))

    # Fill remaining clusters with actual image pixels using seeded LCG
    additional_needed = cluster_count - len(clusters)
    if additional_needed > 0:
        rng = _Random(0x42688)
        indices: List[int] = []
        for _ in range(additional_needed):
            index = rng.next_range(len(points))
            while index in indices:
                index = rng.next_range(len(points))
            indices.append(index)
        for index in indices:
            clusters.append(points[index])

    # Initialize assignments
    cluster_indices = [i % cluster_count for i in range(len(points))]

    # Distance matrix and sorted index matrix
    distance_to_index_matrix: List[List[List]] = [
        [[0.0, j] for j in range(cluster_count)]
        for _ in range(cluster_count)
    ]
    pixel_count_sums = [0] * cluster_count

    for iteration in range(10):
        points_moved = 0

        # Compute inter-cluster distance matrix
        for i in range(cluster_count):
            for j in range(i + 1, cluster_count):
                dist = _lab_distance_squared(clusters[i], clusters[j])
                distance_to_index_matrix[j][i][0] = dist
                distance_to_index_matrix[j][i][1] = i
                distance_to_index_matrix[i][j][0] = dist
                distance_to_index_matrix[i][j][1] = j

            # Sort row by distance
            distance_to_index_matrix[i].sort(key=lambda x: x[0])

        # Assignment step: find nearest cluster for each point
        for i in range(len(points)):
            point = points[i]
            prev_idx = cluster_indices[i]
            prev_dist = _lab_distance_squared(point, clusters[prev_idx])

            min_dist = prev_dist
            new_idx = -1

            for j in range(cluster_count):
                # Triangle inequality: skip if inter-cluster dist >= 4 * current dist
                if distance_to_index_matrix[prev_idx][j][0] >= 4.0 * prev_dist:
                    continue

                dist = _lab_distance_squared(point, clusters[j])
                if dist < min_dist:
                    min_dist = dist
                    new_idx = j

            if new_idx != -1:
                points_moved += 1
                cluster_indices[i] = new_idx

        # Early stop
        if points_moved == 0 and iteration > 0:
            break

        # Update step: compute new centroids as weighted mean in Lab space
        component_l = [0.0] * cluster_count
        component_a = [0.0] * cluster_count
        component_b = [0.0] * cluster_count
        for k in range(cluster_count):
            pixel_count_sums[k] = 0

        for i in range(len(points)):
            cidx = cluster_indices[i]
            pt = points[i]
            count = pixel_to_count[unique_pixels[i]]
            pixel_count_sums[cidx] += count
            component_l[cidx] += pt[0] * count
            component_a[cidx] += pt[1] * count
            component_b[cidx] += pt[2] * count

        for i in range(cluster_count):
            count = pixel_count_sums[i]
            if count == 0:
                clusters[i] = (0.0, 0.0, 0.0)
            else:
                clusters[i] = (
                    component_l[i] / count,
                    component_a[i] / count,
                    component_b[i] / count,
                )

    # Build result: convert cluster centroids from Lab to ARGB with populations
    cluster_argbs: List[int] = []
    cluster_populations: List[int] = []

    for i in range(cluster_count):
        count = pixel_count_sums[i]
        if count == 0:
            continue

        lab = clusters[i]
        cr, cg, cb = lab_to_rgb(lab[0], lab[1], lab[2])
        argb = _argb_from_rgb(cr, cg, cb)

        if argb in cluster_argbs:
            continue

        cluster_argbs.append(argb)
        cluster_populations.append(count)

    color_to_count: Dict[int, int] = {}
    for i in range(len(cluster_argbs)):
        color_to_count[cluster_argbs[i]] = cluster_populations[i]

    return color_to_count


# =============================================================================
# Score Algorithm - ranks colors for UI theme suitability
# =============================================================================

# Score constants matching material-color-utilities
TARGET_CHROMA = 48.0
WEIGHT_PROPORTION = 0.7
WEIGHT_CHROMA_ABOVE = 0.3
WEIGHT_CHROMA_BELOW = 0.1
CUTOFF_CHROMA = 5.0
CUTOFF_EXCITED_PROPORTION = 0.01
FALLBACK_COLOR_ARGB = 0xFF4285F4  # Google Blue


def _sanitize_degrees(degrees: float) -> int:
    """Sanitize degrees to 0-359 range."""
    return int(degrees) % 360


def _difference_degrees(a: float, b: float) -> float:
    """Calculate the shortest distance between two angles."""
    diff = abs(a - b)
    return min(diff, 360.0 - diff)


def score_colors(
    color_to_population: Dict[int, int],
    desired: int = 4,
    fallback_color: int = FALLBACK_COLOR_ARGB,
    filter_colors: bool = True,
) -> List[int]:
    """
    Rank colors based on suitability for UI themes.

    Given a map of colors to population counts, removes unsuitable colors
    and ranks the rest based on chroma and proportion.

    Args:
        color_to_population: Dict mapping ARGB colors to pixel counts
        desired: Maximum number of colors to return
        fallback_color: Color to return if no suitable colors found
        filter_colors: Whether to filter out low-chroma/low-proportion colors

    Returns:
        List of ARGB colors sorted by suitability (best first)
    """
    # Import here to avoid circular dependency
    from .hct import Cam16, Hct

    # Build HCT colors and hue population histogram
    colors_hct: List[Tuple[int, Hct]] = []
    hue_population = [0] * 360
    population_sum = 0

    for argb, population in color_to_population.items():
        r = (argb >> 16) & 0xFF
        g = (argb >> 8) & 0xFF
        b = argb & 0xFF

        try:
            hct = Hct.from_rgb(r, g, b)
            colors_hct.append((argb, hct))
            hue = _sanitize_degrees(hct.hue)
            hue_population[hue] += population
            population_sum += population
        except (ValueError, ZeroDivisionError):
            continue

    if not colors_hct or population_sum == 0:
        return [fallback_color]

    # Calculate "excited proportions" - sum of proportions in ±15° hue window
    hue_excited_proportions = [0.0] * 360
    for hue in range(360):
        proportion = hue_population[hue] / population_sum
        for offset in range(-14, 16):
            neighbor_hue = _sanitize_degrees(hue + offset)
            hue_excited_proportions[neighbor_hue] += proportion

    # Score each color
    scored_hct: List[Tuple[int, Hct, float]] = []
    for argb, hct in colors_hct:
        hue = _sanitize_degrees(round(hct.hue))
        proportion = hue_excited_proportions[hue]

        # Filter by chroma and proportion
        if filter_colors:
            if hct.chroma < CUTOFF_CHROMA:
                continue
            if proportion <= CUTOFF_EXCITED_PROPORTION:
                continue

        # Proportion score (70% weight)
        proportion_score = proportion * 100.0 * WEIGHT_PROPORTION

        # Chroma score
        if hct.chroma < TARGET_CHROMA:
            chroma_weight = WEIGHT_CHROMA_BELOW
        else:
            chroma_weight = WEIGHT_CHROMA_ABOVE
        chroma_score = (hct.chroma - TARGET_CHROMA) * chroma_weight

        score = proportion_score + chroma_score
        scored_hct.append((argb, hct, score))

    if not scored_hct:
        return [fallback_color]

    # Sort by score descending
    scored_hct.sort(key=lambda x: -x[2])

    # Deduplicate by hue distance - maximize hue diversity
    # Start at 90° (max for 4 colors), decrease to 15° minimum
    chosen_colors: List[Tuple[int, Hct]] = []

    for diff_degrees in range(90, 14, -1):
        chosen_colors.clear()
        for argb, hct, score in scored_hct:
            # Check if this hue is far enough from all chosen colors
            is_duplicate = False
            for chosen_argb, chosen_hct in chosen_colors:
                if _difference_degrees(hct.hue, chosen_hct.hue) < diff_degrees:
                    is_duplicate = True
                    break

            if not is_duplicate:
                chosen_colors.append((argb, hct))

            if len(chosen_colors) >= desired:
                break

        if len(chosen_colors) >= desired:
            break

    if not chosen_colors:
        return [fallback_color]

    return [argb for argb, hct in chosen_colors]


def extract_source_color(
    pixels: List[Tuple[int, int, int]],
    fallback_color: int = FALLBACK_COLOR_ARGB,
) -> int:
    """
    Extract the primary source color from image pixels.

    Uses Wu + WSMeans quantizer (QuantizerCelebi) + Score algorithm matching
    matugen/material-color-utilities.

    Args:
        pixels: List of (R, G, B) tuples
        fallback_color: Color to return if extraction fails

    Returns:
        Source color in ARGB format
    """
    from .hct import Cam16

    if not pixels:
        return fallback_color

    # Quantize using Wu + WSMeans (QuantizerCelebi pipeline like matugen)
    wu_result = quantize_wu(pixels, max_colors=128)
    starting_clusters = list(wu_result.keys())
    color_to_count = quantize_wsmeans(pixels, 128, starting_clusters)

    # Filter out low-chroma colors before scoring (like matugen)
    filtered = {}
    for argb, count in color_to_count.items():
        r = (argb >> 16) & 0xFF
        g = (argb >> 8) & 0xFF
        b = argb & 0xFF
        try:
            cam = Cam16.from_rgb(r, g, b)
            if cam.chroma >= 5.0:
                filtered[argb] = count
        except (ValueError, ZeroDivisionError):
            continue

    if not filtered:
        filtered = color_to_count

    # Score and rank colors
    ranked = score_colors(filtered, desired=4, fallback_color=fallback_color)

    return ranked[0] if ranked else fallback_color


def source_color_to_rgb(argb: int) -> Tuple[int, int, int]:
    """Convert ARGB integer to RGB tuple."""
    return _rgb_from_argb(argb)
