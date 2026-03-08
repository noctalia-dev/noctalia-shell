#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D dataSource;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec4 lineColor1;
  vec4 lineColor2;
  float count1;
  float count2;
  float scroll1;
  float scroll2;
  float lineWidth;
  float graphFillOpacity;
  float texWidth;
  float resY;
  float aaSize;
};

// Sample normalized value from data texture
// channel 0 = primary (R), channel 1 = secondary (G)
float fetchData(float idx, int ch) {
  float i = clamp(idx, 0.0, texWidth - 1.0);
  float u = (floor(i) + 0.5) / texWidth;
  vec4 t = texture(dataSource, vec2(u, 0.5));
  return ch == 0 ? t.r : t.g;
}

// Cubic Hermite interpolation with reduced tangent scale for smooth curves
float cubicHermite(float y0, float y1, float y2, float y3, float t) {
  float m1 = (y2 - y0) * 0.25;
  float m2 = (y3 - y1) * 0.25;

  float t2 = t * t;
  float t3 = t2 * t;
  return (2.0 * t3 - 3.0 * t2 + 1.0) * y1
       + (t3 - 2.0 * t2 + t) * m1
       + (-2.0 * t3 + 3.0 * t2) * y2
       + (t3 - t2) * m2;
}

// Evaluate curve at fractional data index
float evalCurve(float dataIdx, int ch) {
  float i = floor(dataIdx);
  float t = dataIdx - i;
  return cubicHermite(
    fetchData(i - 1.0, ch),
    fetchData(i, ch),
    fetchData(i + 1.0, ch),
    fetchData(i + 2.0, ch),
    t
  );
}

// Premultiplied alpha over compositing
vec4 blendOver(vec4 src, vec4 dst) {
  return src + dst * (1.0 - src.a);
}

void main() {
  vec2 uv = qt_TexCoord0;
  float normY = 1.0 - uv.y; // 0 = bottom, 1 = top

  vec4 result = vec4(0.0);
  float halfW = lineWidth * 0.5;

  // Primary line
  if (count1 >= 4.0) {
    float segs = count1 - 3.0;
    float di = 2.0 + scroll1 + uv.x * segs;
    float pixStep1 = dFdx(di);
    float cy = evalCurve(di, 0);
    float cyNext = evalCurve(di + pixStep1, 0);

    // Fill below curve (gradient: opaque at top, transparent at bottom)
    if (graphFillOpacity > 0.0 && normY <= cy) {
      float a = graphFillOpacity * normY * lineColor1.a;
      result = blendOver(vec4(lineColor1.rgb * a, a), result);
    }

    // Perpendicular distance to the line segment between adjacent samples
    float slope1 = (cyNext - cy) * resY;
    float vDist1 = (normY - cy) * resY;
    float dist1 = abs(vDist1) * inversesqrt(slope1 * slope1 + 1.0);
    float sa = smoothstep(halfW + aaSize, halfW, dist1) * lineColor1.a;
    result = blendOver(vec4(lineColor1.rgb * sa, sa), result);
  }

  // Secondary line
  if (count2 >= 4.0) {
    float segs = count2 - 3.0;
    float di = 2.0 + scroll2 + uv.x * segs;
    float pixStep2 = dFdx(di);
    float cy = evalCurve(di, 1);
    float cyNext = evalCurve(di + pixStep2, 1);

    if (graphFillOpacity > 0.0 && normY <= cy) {
      float a = graphFillOpacity * normY * lineColor2.a;
      result = blendOver(vec4(lineColor2.rgb * a, a), result);
    }

    float slope2 = (cyNext - cy) * resY;
    float vDist2 = (normY - cy) * resY;
    float dist2 = abs(vDist2) * inversesqrt(slope2 * slope2 + 1.0);
    float sa = smoothstep(halfW + aaSize, halfW, dist2) * lineColor2.a;
    result = blendOver(vec4(lineColor2.rgb * sa, sa), result);
  }

  fragColor = result * qt_Opacity;
}
