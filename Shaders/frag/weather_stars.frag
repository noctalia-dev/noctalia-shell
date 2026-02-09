#version 450
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float itemWidth;
    float itemHeight;
    vec4 bgColor;
    float cornerRadius;
} ubuf;

// Signed distance function for rounded rectangle
float roundedBoxSDF(vec2 center, vec2 size, float radius) {
    vec2 q = abs(center) - size + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

float hash(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

vec2 hash2(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(vec2(p.x * p.y, p.y * p.x));
}

float stars(vec2 uv, float density, float iTime) {
    vec2 gridUV = uv * density;
    vec2 gridID = floor(gridUV);
    vec2 gridPos = fract(gridUV);

    float starField = 0.0;

    // Check neighboring cells for stars
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            vec2 offset = vec2(float(x), float(y));
            vec2 cellID = gridID + offset;

            // Random position within cell
            vec2 starPos = hash2(cellID);

            // Only create a star for some cells (sparse distribution)
            float starChance = hash(cellID + vec2(12.345, 67.890));
            if (starChance > 0.85) {
                // Star position in grid space
                vec2 toStar = (offset + starPos - gridPos);
                float dist = length(toStar) * density; // Scale distance to pixel space

                float starSize = 1.5;

                // Star brightness variation
                float brightness = hash(cellID + vec2(23.456, 78.901)) * 0.6 + 0.4;

                // Twinkling effect
                float twinkleSpeed = hash(cellID + vec2(34.567, 89.012)) * 3.0 + 2.0;
                float twinklePhase = iTime * twinkleSpeed + hash(cellID) * 6.28;
                float twinkle = pow(sin(twinklePhase) * 0.5 + 0.5, 3.0); // Sharp on/off

                // Sharp star core
                float star = 0.0;
                if (dist < starSize) {
                    star = 1.0 * brightness * (0.3 + twinkle * 0.7);

                    // Add tiny cross-shaped glow for brighter stars
                    if (brightness > 0.7) {
                        float crossGlow = max(
                            exp(-abs(toStar.x) * density * 5.0),
                            exp(-abs(toStar.y) * density * 5.0)
                        ) * 0.3 * twinkle;
                        star += crossGlow;
                    }
                }

                starField += star;
            }
        }
    }

    return starField;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float iTime = ubuf.time * 0.01;

    // Base background color
    vec4 col = vec4(ubuf.bgColor.rgb, 1.0);

    // Aspect ratio for consistent stars
    float aspect = ubuf.itemWidth / ubuf.itemHeight;
    vec2 uvAspect = vec2(uv.x * aspect, uv.y);

    // Generate multiple layers of stars at different densities
    float stars1 = stars(uvAspect, 40.0, iTime);                         // Tiny distant stars
    float stars2 = stars(uvAspect + vec2(0.5, 0.3), 25.0, iTime * 1.3);  // Small stars
    float stars3 = stars(uvAspect + vec2(0.25, 0.7), 15.0, iTime * 0.9); // Bigger stars

    // Star colors with slight variation
    vec3 starColor1 = vec3(0.85, 0.9, 1.0);    // Faint blue-white
    vec3 starColor2 = vec3(0.95, 0.97, 1.0);   // White
    vec3 starColor3 = vec3(1.0, 0.98, 0.95);   // Warm white

    // Combine star layers
    vec3 starsRGB = starColor1 * stars1 * 0.6 +
    starColor2 * stars2 * 0.8 +
    starColor3 * stars3 * 1.0;

    float starsAlpha = clamp(stars1 * 0.6 + stars2 * 0.8 + stars3, 0.0, 1.0);

    // Apply rounded corner mask
    vec2 pixelPos = qt_TexCoord0 * vec2(ubuf.itemWidth, ubuf.itemHeight);
    vec2 center = pixelPos - vec2(ubuf.itemWidth, ubuf.itemHeight) * 0.5;
    vec2 halfSize = vec2(ubuf.itemWidth, ubuf.itemHeight) * 0.5;
    float dist = roundedBoxSDF(center, halfSize, ubuf.cornerRadius);
    float cornerMask = 1.0 - smoothstep(-1.0, 0.0, dist);

    // Add stars on top
    vec3 resultRGB = starsRGB * starsAlpha + col.rgb * (1.0 - starsAlpha);
    float resultAlpha = starsAlpha + col.a * (1.0 - starsAlpha);

    // Apply global opacity and corner mask
    float finalAlpha = resultAlpha * ubuf.qt_Opacity * cornerMask;
    fragColor = vec4(resultRGB * (finalAlpha / max(resultAlpha, 0.001)), finalAlpha);
}