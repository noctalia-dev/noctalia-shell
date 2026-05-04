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

// Squared distance from point p to line segment a→b
float segDistSq(vec2 p, vec2 a, vec2 b) {
  vec2 ab = b - a;
  float len2 = dot(ab, ab);
  float t = len2 > 0.0 ? clamp(dot(p - a, ab) / len2, 0.0, 1.0) : 0.0;
  vec2 proj = a + t * ab;
  vec2 d = p - proj;
  return dot(d, d);
}

// Minimum distance from fragment to curve via multi-segment sampling.
// Samples the curve at 9 half-pixel-spaced x-positions (±2px neighborhood)
// and returns the minimum distance to the 8 line segments between them.
float curveDistance(float dataIdx, float pixStep, float normY, int ch) {
  vec2 frag = vec2(0.0, normY * resY);

  float px = -2.0;
  float py = evalCurve(dataIdx - 2.0 * pixStep, ch) * resY;
  vec2 d0 = frag - vec2(px, py);
  float best = dot(d0, d0);

  for (int i = 1; i <= 8; i++) {
    float cx = -2.0 + float(i) * 0.5;
    float cy = evalCurve(dataIdx + cx * pixStep, ch) * resY;
    best = min(best, segDistSq(frag, vec2(px, py), vec2(cx, cy)));
    px = cx;
    py = cy;
  }

  return sqrt(best);
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
    float pixStep = dFdx(di);
    float cy = evalCurve(di, 0);
    float cyNext = evalCurve(di + pixStep, 0);

    // Fill below curve (gradient: opaque at top, transparent at bottom)
    if (graphFillOpacity > 0.0 && normY <= cy) {
      float a = graphFillOpacity * normY * lineColor1.a;
      result = blendOver(vec4(lineColor1.rgb * a, a), result);
    }

    // Multi-segment distance for accurate AA at peaks and steep sections.
    // AA width derived analytically from curve slope: (|sinθ|+|cosθ|)
    // gives the ideal SDF fwidth (~1.0–1.41) without GPU derivative noise.
    float dist = curveDistance(di, pixStep, normY, 0);
    float slope1 = (cyNext - cy) * resY;
    float aa = (abs(slope1) + 1.0) * inversesqrt(slope1 * slope1 + 1.0) * aaSize * 2.0;
    float sa = smoothstep(halfW + aa, halfW, dist) * lineColor1.a;
    result = blendOver(vec4(lineColor1.rgb * sa, sa), result);
  }

  // Secondary line
  if (count2 >= 4.0) {
    float segs = count2 - 3.0;
    float di = 2.0 + scroll2 + uv.x * segs;
    float pixStep = dFdx(di);
    float cy = evalCurve(di, 1);
    float cyNext = evalCurve(di + pixStep, 1);

    if (graphFillOpacity > 0.0 && normY <= cy) {
      float a = graphFillOpacity * normY * lineColor2.a;
      result = blendOver(vec4(lineColor2.rgb * a, a), result);
    }

    float dist = curveDistance(di, pixStep, normY, 1);
    float slope2 = (cyNext - cy) * resY;
    float aa = (abs(slope2) + 1.0) * inversesqrt(slope2 * slope2 + 1.0) * aaSize * 2.0;
    float sa = smoothstep(halfW + aa, halfW, dist) * lineColor2.a;
    result = blendOver(vec4(lineColor2.rgb * sa, sa), result);
  }

  fragColor = result * qt_Opacity;
}
