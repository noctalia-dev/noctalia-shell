#include "render/programs/SpinnerProgram.h"

#include <array>
#include <stdexcept>

namespace {

constexpr char kVertexShaderSource[] = R"(
precision highp float;

attribute vec2 a_position;
uniform vec2 u_surface_size;
uniform vec4 u_quad_rect;
uniform vec4 u_rect;
uniform float u_rotation;
uniform float u_scale;
varying vec2 v_pixel;

vec2 to_ndc(vec2 pixel_pos) {
    vec2 normalized = pixel_pos / u_surface_size;
    return vec2(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0);
}

void main() {
    vec2 local = a_position * u_quad_rect.zw;
    vec2 center = u_quad_rect.zw * 0.5;
    vec2 offset = (local - center) * u_scale;
    float cs = cos(u_rotation);
    float sn = sin(u_rotation);
    vec2 rotated = vec2(offset.x * cs - offset.y * sn,
                        offset.x * sn + offset.y * cs);
    vec2 pixel_pos = u_quad_rect.xy + center + rotated;
    v_pixel = u_quad_rect.xy + local;
    gl_Position = vec4(to_ndc(pixel_pos), 0.0, 1.0);
}
)";

constexpr char kFragmentShaderSource[] = R"(
precision highp float;

uniform vec4 u_rect;
uniform vec4 u_color;
uniform float u_thickness;
varying vec2 v_pixel;

const float PI = 3.14159265359;
const float NOTCH_ANGLE = 0.0;

void main() {
    vec2 center = u_rect.xy + u_rect.zw * 0.5;
    float radius = min(u_rect.z, u_rect.w) * 0.5 - u_thickness * 0.5;
    vec2 p = v_pixel - center;
    float dist = length(p);

    // Ring SDF
    float ring = abs(dist - radius) - u_thickness * 0.5;
    float aa = 0.85;
    float ringMask = 1.0 - smoothstep(-aa, aa, ring);

    // Notch: hide a 90-degree arc at a fixed position (rotation is handled by the vertex shader)
    float theta = atan(p.y, p.x);
    float diff = mod(theta - NOTCH_ANGLE + 3.0 * PI, 2.0 * PI) - PI;
    float notchHalf = PI * 0.25;
    float notchMask = smoothstep(-0.08, 0.08, abs(diff) - notchHalf);

    float alpha = ringMask * notchMask * u_color.a;
    if (alpha <= 0.0) {
        discard;
    }

    gl_FragColor = vec4(u_color.rgb * alpha, alpha);
}
)";

} // namespace

void SpinnerProgram::ensureInitialized() {
  if (m_program.isValid()) {
    return;
  }

  m_program.create(kVertexShaderSource, kFragmentShaderSource);
  m_positionLocation = glGetAttribLocation(m_program.id(), "a_position");
  m_surfaceSizeLocation = glGetUniformLocation(m_program.id(), "u_surface_size");
  m_quadRectLocation = glGetUniformLocation(m_program.id(), "u_quad_rect");
  m_rectLocation = glGetUniformLocation(m_program.id(), "u_rect");
  m_colorLocation = glGetUniformLocation(m_program.id(), "u_color");
  m_thicknessLocation = glGetUniformLocation(m_program.id(), "u_thickness");
  m_rotationLocation = glGetUniformLocation(m_program.id(), "u_rotation");
  m_scaleLocation = glGetUniformLocation(m_program.id(), "u_scale");

  if (m_positionLocation < 0 || m_surfaceSizeLocation < 0 || m_quadRectLocation < 0 || m_rectLocation < 0 ||
      m_colorLocation < 0 || m_thicknessLocation < 0 || m_rotationLocation < 0 || m_scaleLocation < 0) {
    throw std::runtime_error("failed to query spinner shader locations");
  }
}

void SpinnerProgram::destroy() {
  m_program.destroy();
  m_positionLocation = -1;
  m_surfaceSizeLocation = -1;
  m_quadRectLocation = -1;
  m_rectLocation = -1;
  m_colorLocation = -1;
  m_thicknessLocation = -1;
  m_rotationLocation = -1;
  m_scaleLocation = -1;
}

void SpinnerProgram::draw(float surfaceWidth, float surfaceHeight, float x, float y, float width, float height,
                          const SpinnerStyle& style, float rotation, float scale) const {
  if (!m_program.isValid() || width <= 0.0f || height <= 0.0f) {
    return;
  }

  const std::array<GLfloat, 12> vertices = {
      0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
  };

  const float padding = style.thickness + 2.0f;
  const float quadX = x - padding;
  const float quadY = y - padding;
  const float quadWidth = width + padding * 2.0f;
  const float quadHeight = height + padding * 2.0f;

  glUseProgram(m_program.id());
  glUniform2f(m_surfaceSizeLocation, surfaceWidth, surfaceHeight);
  glUniform4f(m_quadRectLocation, quadX, quadY, quadWidth, quadHeight);
  glUniform4f(m_rectLocation, x, y, width, height);
  glUniform4f(m_colorLocation, style.color.r, style.color.g, style.color.b, style.color.a);
  glUniform1f(m_thicknessLocation, style.thickness);
  glUniform1f(m_rotationLocation, rotation);
  glUniform1f(m_scaleLocation, scale);
  glVertexAttribPointer(m_positionLocation, 2, GL_FLOAT, GL_FALSE, 0, vertices.data());
  glEnableVertexAttribArray(m_positionLocation);
  glDrawArrays(GL_TRIANGLES, 0, 6);
  glDisableVertexAttribArray(m_positionLocation);
}
