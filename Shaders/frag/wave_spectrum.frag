#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(binding = 1) uniform sampler2D dataSource;

layout(std140, binding = 0) uniform buf {
  mat4 qt_Matrix;
  float qt_Opacity;
  vec4 fillColor;
  float count;
  float texWidth;
  float vertical;
};

// Sample amplitude from data texture (R channel)
float fetchData(float idx) {
  float i = clamp(idx, 0.0, texWidth - 1.0);
  float u = (floor(i) + 0.5) / texWidth;
  return texture(dataSource, vec2(u, 0.5)).r;
}

// Cubic Hermite interpolation for smooth wave curves
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

// Evaluate interpolated amplitude at fractional data index
float evalCurve(float dataIdx) {
  float i = floor(dataIdx);
  float t = dataIdx - i;
  return cubicHermite(
    fetchData(i - 1.0),
    fetchData(i),
    fetchData(i + 1.0),
    fetchData(i + 2.0),
    t
  );
}

void main() {
  vec2 uv = qt_TexCoord0;

  // Swap axes for vertical mode
  float axisPos = (vertical > 0.5) ? uv.y : uv.x;
  float crossPos = (vertical > 0.5) ? uv.x : uv.y;

  // Mirror: value[0] at center, value[count-1] at edges
  float distFromCenter = abs(axisPos - 0.5) * 2.0;
  float dataIdx = distFromCenter * max(count - 1.0, 1.0);

  // Interpolated amplitude, clamped to valid range
  float amplitude = clamp(evalCurve(dataIdx), 0.0, 1.0);

  // Wave fills center ± amplitude/2 in the cross axis
  float halfAmp = amplitude * 0.5;
  float distFromMid = abs(crossPos - 0.5);

  // Antialiased edge (~1px smooth transition)
  float edge = fwidth(crossPos) * 1.5;
  float mask = smoothstep(halfAmp + edge, halfAmp - edge, distFromMid);

  // Premultiplied alpha output
  float a = mask * fillColor.a;
  fragColor = vec4(fillColor.rgb * a, a) * qt_Opacity;
}
