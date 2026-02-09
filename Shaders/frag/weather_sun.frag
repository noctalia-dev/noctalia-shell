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

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// God rays originating from sun position
float sunRays(vec2 uv, vec2 sunPos, float iTime) {
    vec2 toSun = uv - sunPos;
    float angle = atan(toSun.y, toSun.x);
    float dist = length(toSun);

    float rayCount = 7;

    // Radial pattern
    float rays = sin(angle * rayCount + sin(iTime * 0.25)) * 0.5 + 0.5;
    rays = pow(rays, 3.0);

    // Fade with distance
    float falloff = 1.0 - smoothstep(0.0, 1.2, dist);

    return rays * falloff * 0.15;
}

// Atmospheric shimmer / heat haze
float atmosphericShimmer(vec2 uv, float iTime) {
    // Multiple layers of noise for complexity
    float n1 = noise(uv * 5.0 + vec2(iTime * 0.1, iTime * 0.05));
    float n2 = noise(uv * 8.0 - vec2(iTime * 0.08, iTime * 0.12));
    float n3 = noise(uv * 12.0 + vec2(iTime * 0.15, -iTime * 0.1));

    return (n1 * 0.5 + n2 * 0.3 + n3 * 0.2) * 0.15;
}

float sunCore(vec2 uv, vec2 sunPos, float iTime) {
    vec2 toSun = uv - sunPos;
    float dist = length(toSun);

    // Main bright spot
    float mainFlare = exp(-dist * 15.0) * 2.0;

    // Secondary reflection spots along the line
    float flares = 0.0;
    for (int i = 1; i <= 3; i++) {
        vec2 flarePos = sunPos + toSun * float(i) * 0.3;
        float flareDist = length(uv - flarePos);
        float flareSize = 0.02 + float(i) * 0.01;
        flares += smoothstep(flareSize * 2.0, flareSize * 0.5, flareDist) * (0.3 / float(i));
    }

    // Pulsing effect
    float pulse = sin(iTime) * 0.1 + 0.9;

    return (mainFlare + flares) * pulse;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float iTime = ubuf.time * 0.08;

    // Sample the source
    vec4 col = vec4(ubuf.bgColor.rgb, 1.0);

    vec2 sunPos = vec2(0.85, 0.2);

    // Aspect ratio correction
    float aspect = ubuf.itemWidth / ubuf.itemHeight;
    vec2 uvAspect = vec2(uv.x * aspect, uv.y);
    vec2 sunPosAspect = vec2(sunPos.x * aspect, sunPos.y);

    // Generate sunny effects
    float rays = sunRays(uvAspect, sunPosAspect, iTime);
    float shimmerEffect = atmosphericShimmer(uv, iTime);
    float flare = sunCore(uvAspect, sunPosAspect, iTime);

    // Warm sunny colors
    vec3 sunColor = vec3(1.0, 0.95, 0.7);      // Warm golden yellow
    vec3 skyColor = vec3(0.9, 0.95, 1.0);      // Light blue tint
    vec3 shimmerColor = vec3(1.0, 0.98, 0.85); // Subtle warm shimmer

    // Apply rounded corner mask
    vec2 pixelPos = qt_TexCoord0 * vec2(ubuf.itemWidth, ubuf.itemHeight);
    vec2 center = pixelPos - vec2(ubuf.itemWidth, ubuf.itemHeight) * 0.5;
    vec2 halfSize = vec2(ubuf.itemWidth, ubuf.itemHeight) * 0.5;
    float dist = roundedBoxSDF(center, halfSize, ubuf.cornerRadius);
    float cornerMask = 1.0 - smoothstep(-1.0, 0.0, dist);

    vec3 resultRGB = col.rgb;
    float resultAlpha = col.a;

    // Add sun rays
    vec3 raysContribution = sunColor * rays;
    float raysAlpha = rays * 0.4;
    resultRGB = raysContribution + resultRGB * (1.0 - raysAlpha);
    resultAlpha = raysAlpha + resultAlpha * (1.0 - raysAlpha);

    // Add atmospheric shimmer
    vec3 shimmerContribution = shimmerColor * shimmerEffect;
    float shimmerAlpha = shimmerEffect * 0.1;
    resultRGB = shimmerContribution + resultRGB * (1.0 - shimmerAlpha);
    resultAlpha = shimmerAlpha + resultAlpha * (1.0 - shimmerAlpha);

    // Add bright sun core
    vec3 flareContribution = sunColor * flare;
    float flareAlpha = clamp(flare, 0.0, 1.0) * 0.6;
    resultRGB = flareContribution + resultRGB * (1.0 - flareAlpha);
    resultAlpha = flareAlpha + resultAlpha * (1.0 - flareAlpha);

    // Overall warm sunny tint
    resultRGB = mix(resultRGB, resultRGB * vec3(1.08, 1.04, 0.98), 0.15);

    // Apply global opacity and corner mask
    float finalAlpha = resultAlpha * ubuf.qt_Opacity * cornerMask;
    fragColor = vec4(resultRGB * (finalAlpha / max(resultAlpha, 0.001)), finalAlpha);
}