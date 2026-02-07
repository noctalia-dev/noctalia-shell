// ===== wp_pixelate.frag =====
#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float maxBlockSize;  // Maximum block size in pixels (default 64)

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

void main() {
    vec2 uv = qt_TexCoord0;

    // Triangle wave: pixelation peaks at progress=0.5
    float pixelIntensity = 1.0 - abs(2.0 * ubuf.progress - 1.0);

    // Block size ramps from 1 pixel to maxBlockSize at peak, then back down
    float blockSize = max(1.0, ubuf.maxBlockSize * pixelIntensity);

    // Snap UV to block grid in pixel space
    vec2 screenSize = vec2(ubuf.screenWidth, ubuf.screenHeight);
    vec2 pixelCoord = uv * screenSize;
    vec2 snappedPixel = floor(pixelCoord / blockSize) * blockSize + blockSize * 0.5;
    vec2 snappedUV = snappedPixel / screenSize;

    // Sample both textures at the snapped (pixelated) UV
    vec4 color1 = sampleWithFillMode(source1, snappedUV, ubuf.imageWidth1, ubuf.imageHeight1, ubuf.isSolid1, ubuf.solidColor1);
    vec4 color2 = sampleWithFillMode(source2, snappedUV, ubuf.imageWidth2, ubuf.imageHeight2, ubuf.isSolid2, ubuf.solidColor2);

    // Crossfade concentrated around the peak pixelation (progress ~0.5)
    float blend = smoothstep(0.4, 0.6, ubuf.progress);

    fragColor = mix(color1, color2, blend) * ubuf.qt_Opacity;
}
