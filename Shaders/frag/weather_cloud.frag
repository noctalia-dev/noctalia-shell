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
    float alternative;
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

// Perlin-like noise
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smooth interpolation
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Turbulent noise for natural fog
float turbulence(vec2 p, float iTime) {
    float t = 0.0;
    float scale = 1.0;
    for(int i = 0; i < 5; i++) {
        t += abs(noise(p * scale + iTime * 0.1 * scale)) / scale;
        scale *= 2.0;
    }
    return t;
}

void main() {
    vec2 uv = qt_TexCoord0;

    vec4 col = vec4(ubuf.bgColor.rgb, 1.0);

    // Different parameters for fog vs clouds
    float timeSpeed, layerScale1, layerScale2, layerScale3;
    float flowSpeed1, flowSpeed2;
    float densityMin, densityMax;
    float baseOpacity;
    float pulseAmount;

    if (ubuf.alternative > 0.5) {
        // Fog: slower, larger scale, more uniform
        timeSpeed = 0.03;
        layerScale1 = 1.0;
        layerScale2 = 2.5;
        layerScale3 = 2.0;
        flowSpeed1 = 0.00;
        flowSpeed2 = 0.02;
        densityMin = 0.1;
        densityMax = 0.9;
        baseOpacity = 0.75;
        pulseAmount = 0.05;
    } else {
        // Clouds: faster, smaller scale, puffier
        timeSpeed = 0.08;
        layerScale1 = 2.0;
        layerScale2 = 4.0;
        layerScale3 = 6.0;
        flowSpeed1 = 0.03;
        flowSpeed2 = 0.04;
        densityMin = 0.35;
        densityMax = 0.75;
        baseOpacity = 0.4;
        pulseAmount = 0.15;
    }

    float iTime = ubuf.time * timeSpeed;

    // Create flowing patterns with multiple layers
    vec2 flow1 = vec2(iTime * flowSpeed1, iTime * flowSpeed1 * 0.7);
    vec2 flow2 = vec2(-iTime * flowSpeed2, iTime * flowSpeed2 * 0.8);

    float fog1 = noise(uv * layerScale1 + flow1);
    float fog2 = noise(uv * layerScale2 + flow2);
    float fog3 = turbulence(uv * layerScale3, iTime);

    float fogPattern = fog1 * 0.5 + fog2 * 0.3 + fog3 * 0.2;
    float fogDensity = smoothstep(densityMin, densityMax, fogPattern);

    // Gentle pulsing
    float pulse = sin(iTime * 0.4) * pulseAmount + (1.0 - pulseAmount);
    fogDensity *= pulse;

    vec3 hazeColor = vec3(0.88, 0.90, 0.93);
    float hazeOpacity = fogDensity * baseOpacity;
    vec3 fogContribution = hazeColor * hazeOpacity;
    float fogAlpha = hazeOpacity;

    vec3 resultRGB = fogContribution + col.rgb * (1.0 - fogAlpha);
    float resultAlpha = fogAlpha + col.a * (1.0 - fogAlpha);

    // Calculate corner mask
    vec2 pixelPos = qt_TexCoord0 * vec2(ubuf.itemWidth, ubuf.itemHeight);
    vec2 center = pixelPos - vec2(ubuf.itemWidth, ubuf.itemHeight) * 0.5;
    vec2 halfSize = vec2(ubuf.itemWidth, ubuf.itemHeight) * 0.5;
    float dist = roundedBoxSDF(center, halfSize, ubuf.cornerRadius);
    float cornerMask = 1.0 - smoothstep(-1.0, 0.0, dist);

    // Apply global opacity and corner mask
    float finalAlpha = resultAlpha * ubuf.qt_Opacity * cornerMask;
    fragColor = vec4(resultRGB * (finalAlpha / max(resultAlpha, 0.001)), finalAlpha);
}