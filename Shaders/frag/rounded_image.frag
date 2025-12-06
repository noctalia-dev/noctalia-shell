#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D source;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    // Custom properties with non-conflicting names
    float itemWidth;
    float itemHeight;
    float sourceWidth;
    float sourceHeight;
    float cornerRadius;
    float imageOpacity;
    int fillMode;
} ubuf;

// Function to calculate the signed distance from a point to a rounded box
float roundedBoxSDF(vec2 centerPos, vec2 boxSize, float radius) {
    vec2 d = abs(centerPos) - boxSize + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

void main() {
    // Get size from uniforms
    vec2 itemSize = vec2(ubuf.itemWidth, ubuf.itemHeight);
    vec2 sourceSize = vec2(ubuf.sourceWidth, ubuf.sourceHeight);
    float cornerRadius = ubuf.cornerRadius;
    float itemOpacity = ubuf.imageOpacity;
    int fillMode = ubuf.fillMode;

    // Work in pixel space for accurate rounded rectangle calculation
    vec2 pixelPos = qt_TexCoord0 * itemSize;

    // Calculate distance to rounded rectangle edge (in pixels)
    vec2 centerOffset = pixelPos - itemSize * 0.5;
    float distance = roundedBoxSDF(centerOffset, itemSize * 0.5, cornerRadius);

    // Create smooth alpha mask for edge with anti-aliasing
    float alpha = 1.0 - smoothstep(-0.5, 0.5, distance);

    // Calculate UV coordinates based on fill mode
    vec2 imageUV = qt_TexCoord0;

    // fillMode constants from Qt:
    // Image.Stretch = 0
    // Image.PreserveAspectFit = 1
    // Image.PreserveAspectCrop = 2
    // Image.Tile = 3
    // Image.TileVertically = 4
    // Image.TileHorizontally = 5
    // Image.Pad = 6

    if (fillMode == 1) { // PreserveAspectFit
        float itemAspect = itemSize.x / itemSize.y;
        float sourceAspect = sourceSize.x / sourceSize.y;

        if (sourceAspect > itemAspect) {
            // Image is wider than item, letterbox top/bottom
            imageUV.y = (qt_TexCoord0.y - 0.5) * (sourceAspect / itemAspect) + 0.5;
        } else {
            // Image is taller than item, letterbox left/right
            imageUV.x = (qt_TexCoord0.x - 0.5) * (itemAspect / sourceAspect) + 0.5;
        }

        // Make letterbox area transparent
        if (imageUV.x < 0.0 || imageUV.x > 1.0 || imageUV.y < 0.0 || imageUV.y > 1.0) {
            alpha = 0.0;
        }
    } else if (fillMode == 2) { // PreserveAspectCrop
        float itemAspect = itemSize.x / itemSize.y;
        float sourceAspect = sourceSize.x / sourceSize.y;

        if (sourceAspect > itemAspect) {
            // Image is wider than item, crop left/right.
            imageUV.x = (qt_TexCoord0.x - 0.5) * (itemAspect / sourceAspect) + 0.5;
        } else {
            // Image is taller than item, crop top/bottom.
            imageUV.y = (qt_TexCoord0.y - 0.5) * (sourceAspect / itemAspect) + 0.5;
        }
    }
    // For Stretch (0) or other modes, use qt_TexCoord0 as-is

    // Sample the texture
    vec4 color = texture(source, imageUV);

    // Apply the rounded mask and opacity
    float finalAlpha = color.a * alpha * itemOpacity * ubuf.qt_Opacity;
    fragColor = vec4(color.rgb * finalAlpha, finalAlpha);
}