// ===== wp_honeycomb.frag =====
#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float cellSize;      // Size of hexagonal cells in UV space (default 0.04)
    float centerX;       // X coordinate of wave origin (0.0 to 1.0)
    float centerY;       // Y coordinate of wave origin (0.0 to 1.0)
    float aspectRatio;   // Width / Height of the screen

    // Fill mode parameters
    float fillMode;      // 0=center, 1=crop, 2=fit, 3=stretch, 4=repeat
    float imageWidth1;   // Width of source1 image
    float imageHeight1;  // Height of source1 image
    float imageWidth2;   // Width of source2 image
    float imageHeight2;  // Height of source2 image
    float screenWidth;   // Screen width
    float screenHeight;  // Screen height
    vec4 fillColor;      // Fill color for empty areas (default: black)

    // Solid color mode
    float isSolid1;      // 1.0 if source1 is solid color, 0.0 otherwise
    float isSolid2;      // 1.0 if source2 is solid color, 0.0 otherwise
    vec4 solidColor1;    // Solid color for source1
    vec4 solidColor2;    // Solid color for source2
} ubuf;

// Calculate UV coordinates based on fill mode
vec2 calculateUV(vec2 uv, float imgWidth, float imgHeight) {
    float imageAspect = imgWidth / imgHeight;
    float screenAspect = ubuf.screenWidth / ubuf.screenHeight;
    vec2 transformedUV = uv;

    if (ubuf.fillMode < 0.5) {
        // Mode 0: no (center) - No resize, center image at original size
        vec2 screenPixel = uv * vec2(ubuf.screenWidth, ubuf.screenHeight);
        vec2 imageOffset = (vec2(ubuf.screenWidth, ubuf.screenHeight) - vec2(imgWidth, imgHeight)) * 0.5;
        vec2 imagePixel = screenPixel - imageOffset;
        transformedUV = imagePixel / vec2(imgWidth, imgHeight);
    }
    else if (ubuf.fillMode < 1.5) {
        // Mode 1: crop (fill/cover) - Fill screen, crop excess (default)
        float scale = max(ubuf.screenWidth / imgWidth, ubuf.screenHeight / imgHeight);
        vec2 scaledImageSize = vec2(imgWidth, imgHeight) * scale;
        vec2 offset = (scaledImageSize - vec2(ubuf.screenWidth, ubuf.screenHeight)) / scaledImageSize;
        transformedUV = uv * (vec2(1.0) - offset) + offset * 0.5;
    }
    else if (ubuf.fillMode < 2.5) {
        // Mode 2: fit (contain) - Fit inside screen, maintain aspect ratio
        float scale = min(ubuf.screenWidth / imgWidth, ubuf.screenHeight / imgHeight);
        vec2 scaledImageSize = vec2(imgWidth, imgHeight) * scale;
        vec2 offset = (vec2(ubuf.screenWidth, ubuf.screenHeight) - scaledImageSize) * 0.5;

        vec2 screenPixel = uv * vec2(ubuf.screenWidth, ubuf.screenHeight);
        vec2 imagePixel = (screenPixel - offset) / scale;
        transformedUV = imagePixel / vec2(imgWidth, imgHeight);
    }
    else if (ubuf.fillMode < 3.5) {
        // Mode 3: stretch - Use original UV (stretches to fit)
    }
    else {
        // Mode 4: repeat (tile) - Tile image at original size
        vec2 screenPixel = uv * vec2(ubuf.screenWidth, ubuf.screenHeight);
        transformedUV = screenPixel / vec2(imgWidth, imgHeight);
    }

    return transformedUV;
}

// Sample texture with fill mode and handle out-of-bounds
vec4 sampleWithFillMode(sampler2D tex, vec2 uv, float imgWidth, float imgHeight, float isSolid, vec4 solidColor) {
    if (isSolid > 0.5) {
        return solidColor;
    }

    vec2 transformedUV = calculateUV(uv, imgWidth, imgHeight);

    if (ubuf.fillMode > 3.5) {
        return texture(tex, fract(transformedUV));
    }

    if (transformedUV.x < 0.0 || transformedUV.x > 1.0 ||
        transformedUV.y < 0.0 || transformedUV.y > 1.0) {
        return ubuf.fillColor;
    }

    return texture(tex, transformedUV);
}

// Convert cartesian to axial hex coordinates and round to nearest hex center
vec2 hexRound(vec2 axial) {
    // Convert axial (q,r) to cube (x,y,z) where x+y+z=0
    float x = axial.x;
    float z = axial.y;
    float y = -x - z;

    // Round each
    float rx = round(x);
    float ry = round(y);
    float rz = round(z);

    // Fix rounding errors by resetting the component with largest diff
    float dx = abs(rx - x);
    float dy = abs(ry - y);
    float dz = abs(rz - z);

    if (dx > dy && dx > dz) {
        rx = -ry - rz;
    } else if (dy > dz) {
        ry = -rx - rz;
    } else {
        rz = -rx - ry;
    }

    return vec2(rx, rz);
}

void main() {
    vec2 uv = qt_TexCoord0;

    // Sample both textures at original UV
    vec4 color1 = sampleWithFillMode(source1, uv, ubuf.imageWidth1, ubuf.imageHeight1, ubuf.isSolid1, ubuf.solidColor1);
    vec4 color2 = sampleWithFillMode(source2, uv, ubuf.imageWidth2, ubuf.imageHeight2, ubuf.isSolid2, ubuf.solidColor2);

    // Aspect-correct the UV for hex grid so cells appear as regular hexagons
    vec2 aspectUV = vec2(uv.x * ubuf.aspectRatio, uv.y);

    // Convert to axial hex coordinates
    // Hex grid: q axis along x, r axis at 60 degrees
    float size = max(ubuf.cellSize, 0.01);
    float q = (aspectUV.x * (2.0 / 3.0)) / size;
    float r = ((-aspectUV.x / 3.0) + (sqrt(3.0) / 3.0) * aspectUV.y) / size;

    // Round to nearest hex center
    vec2 hex = hexRound(vec2(q, r));

    // Convert hex center back to aspect-corrected UV space
    vec2 hexCenter;
    hexCenter.x = size * (3.0 / 2.0) * hex.x;
    hexCenter.y = size * (sqrt(3.0) * (hex.y + 0.5 * hex.x));

    // Calculate distance from this cell's center to the wave origin (aspect-corrected)
    vec2 origin = vec2(ubuf.centerX * ubuf.aspectRatio, ubuf.centerY);
    float dist = distance(hexCenter, origin);

    // Maximum distance from origin to any corner (for normalization)
    float maxDistX = max(ubuf.centerX * ubuf.aspectRatio, (1.0 - ubuf.centerX) * ubuf.aspectRatio);
    float maxDistY = max(ubuf.centerY, 1.0 - ubuf.centerY);
    float maxDist = length(vec2(maxDistX, maxDistY));

    // Wave expansion (same approach as disc shader):
    // Start radius behind the origin so the smoothstep zone is fully off-screen at progress=0
    float softEdge = 0.15 * maxDist;
    float totalDistance = maxDist + 2.0 * softEdge;
    float radius = -softEdge + ubuf.progress * totalDistance;

    // factor = 0 inside the wave (revealed), 1 outside (not yet reached)
    float factor = smoothstep(radius - softEdge, radius + softEdge, dist);
    float cellProgress = 1.0 - factor;

    fragColor = mix(color1, color2, cellProgress) * ubuf.qt_Opacity;
}
