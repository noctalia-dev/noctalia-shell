#include "render/programs/rect_program.h"

#include <array>
#include <stdexcept>

namespace {

  constexpr char kVertexShaderSource[] = R"(
precision highp float;

attribute vec2 a_position;
uniform vec2 u_surface_size;
uniform vec2 u_quad_size;
uniform vec2 u_rect_origin;
uniform vec2 u_rect_size;
uniform mat3 u_transform;
varying vec2 v_pixel;

vec2 to_ndc(vec2 pixel_pos) {
    vec2 normalized = pixel_pos / u_surface_size;
    return vec2(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0);
}

void main() {
    vec2 local = a_position * u_quad_size;
    vec3 pixel = u_transform * vec3(local, 1.0);
    v_pixel = local - u_rect_origin;
    gl_Position = vec4(to_ndc(pixel.xy), 0.0, 1.0);
}
)";

  constexpr char kFragmentShaderSource[] = R"(
precision highp float;

uniform vec2 u_rect_size;
uniform vec4 u_color;
uniform vec4 u_fill_end_color;
uniform vec4 u_border_color;
uniform int u_fill_mode;
uniform vec2 u_gradient_direction;
uniform vec4 u_radii;  // tl, tr, br, bl
uniform float u_softness;
uniform float u_border_width;
varying vec2 v_pixel;

float rounded_rect_distance(vec2 point, vec2 size, vec4 radii) {
    vec2 half_size = size * 0.5;
    vec2 centered = point - half_size;
    // Select per-corner radius based on quadrant
    float r = centered.x < 0.0
        ? (centered.y < 0.0 ? radii.x : radii.w)
        : (centered.y < 0.0 ? radii.y : radii.z);
    vec2 q = abs(centered) - (half_size - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    float aa = max(u_softness, 0.85);
    vec2 local_point = v_pixel;
    vec2 uv = clamp(local_point / u_rect_size, vec2(0.0), vec2(1.0));

    float outer_distance = rounded_rect_distance(local_point, u_rect_size, u_radii);
    float outer_coverage = 1.0 - smoothstep(-aa, aa, outer_distance);

    float gradient_t = clamp(dot(uv, u_gradient_direction), 0.0, 1.0);
    vec4 fill_base;
    if (u_fill_mode == 0) {
        fill_base = vec4(0.0);
    } else if (u_fill_mode == 1) {
        fill_base = u_color;
    } else {
        fill_base = mix(u_color, u_fill_end_color, gradient_t);
    }

    if (u_border_width <= 0.0 || u_border_color.a <= 0.0) {
        float out_alpha = fill_base.a * outer_coverage;
        if (out_alpha <= 0.0) {
            discard;
        }
        gl_FragColor = vec4(fill_base.rgb * out_alpha, out_alpha);
        return;
    }

    vec4 inner_radii = max(u_radii - vec4(u_border_width), vec4(0.0));
    vec2 inner_size = max(u_rect_size - vec2(u_border_width * 2.0), vec2(0.0));
    vec2 inner_point = local_point - vec2(u_border_width);
    float inner_distance = rounded_rect_distance(inner_point, inner_size, inner_radii);
    float inner_coverage = 1.0 - smoothstep(-aa, aa, inner_distance);

    if (fill_base.a <= 0.0) {
        float ring_coverage = outer_coverage * (1.0 - inner_coverage);
        float out_alpha = u_border_color.a * ring_coverage;
        if (out_alpha <= 0.0) {
            discard;
        }
        gl_FragColor = vec4(u_border_color.rgb * out_alpha, out_alpha);
        return;
    }

    // Fill and border occupy disjoint regions: the fill lives where
    // inner_coverage == 1, the border ring lives where inner_coverage == 0.
    // Mix between them so a translucent fill never sits on top of a
    // full-area border backplane (which would mask its opacity).
    vec3 border_pm = u_border_color.rgb * u_border_color.a;
    vec3 fill_pm = fill_base.rgb * fill_base.a;

    vec3 interior_rgb = mix(border_pm, fill_pm, inner_coverage);
    float interior_a = mix(u_border_color.a, fill_base.a, inner_coverage);

    // Apply outer shape mask
    float out_alpha = interior_a * outer_coverage;
    if (out_alpha <= 0.0) {
        discard;
    }

    // Output premultiplied alpha
    gl_FragColor = vec4(interior_rgb * outer_coverage, out_alpha);
}
)";

} // namespace

void RectProgram::ensureInitialized() {
  if (m_program.isValid()) {
    return;
  }

  m_program.create(kVertexShaderSource, kFragmentShaderSource);
  m_positionLocation = glGetAttribLocation(m_program.id(), "a_position");
  m_surfaceSizeLocation = glGetUniformLocation(m_program.id(), "u_surface_size");
  m_quadSizeLocation = glGetUniformLocation(m_program.id(), "u_quad_size");
  m_rectOriginLocation = glGetUniformLocation(m_program.id(), "u_rect_origin");
  m_rectSizeLocation = glGetUniformLocation(m_program.id(), "u_rect_size");
  m_colorLocation = glGetUniformLocation(m_program.id(), "u_color");
  m_fillEndColorLocation = glGetUniformLocation(m_program.id(), "u_fill_end_color");
  m_borderColorLocation = glGetUniformLocation(m_program.id(), "u_border_color");
  m_fillModeLocation = glGetUniformLocation(m_program.id(), "u_fill_mode");
  m_gradientDirectionLocation = glGetUniformLocation(m_program.id(), "u_gradient_direction");
  m_radiiLocation = glGetUniformLocation(m_program.id(), "u_radii");
  m_softnessLocation = glGetUniformLocation(m_program.id(), "u_softness");
  m_borderWidthLocation = glGetUniformLocation(m_program.id(), "u_border_width");
  m_transformLocation = glGetUniformLocation(m_program.id(), "u_transform");

  if (m_positionLocation < 0 || m_surfaceSizeLocation < 0 || m_quadSizeLocation < 0 || m_rectOriginLocation < 0 ||
      m_rectSizeLocation < 0 || m_colorLocation < 0 || m_fillEndColorLocation < 0 || m_borderColorLocation < 0 ||
      m_fillModeLocation < 0 || m_gradientDirectionLocation < 0 || m_radiiLocation < 0 || m_softnessLocation < 0 ||
      m_borderWidthLocation < 0 || m_transformLocation < 0) {
    throw std::runtime_error("failed to query rounded-rect shader locations");
  }
}

void RectProgram::destroy() {
  m_program.destroy();
  m_positionLocation = -1;
  m_surfaceSizeLocation = -1;
  m_quadSizeLocation = -1;
  m_rectOriginLocation = -1;
  m_rectSizeLocation = -1;
  m_colorLocation = -1;
  m_fillEndColorLocation = -1;
  m_borderColorLocation = -1;
  m_fillModeLocation = -1;
  m_gradientDirectionLocation = -1;
  m_radiiLocation = -1;
  m_softnessLocation = -1;
  m_borderWidthLocation = -1;
  m_transformLocation = -1;
}

void RectProgram::draw(float surfaceWidth, float surfaceHeight, float width, float height,
                       const RoundedRectStyle& style, const Mat3& transform) const {
  if (!m_program.isValid() || width <= 0.0f || height <= 0.0f) {
    return;
  }

  const std::array<GLfloat, 12> vertices = {
      0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
  };

  const float padding = std::max(style.borderWidth + style.softness + 2.0f, 2.0f);
  const float quadWidth = width + padding * 2.0f;
  const float quadHeight = height + padding * 2.0f;
  const float rectOrigin = padding;
  const Mat3 quadTransform = transform * Mat3::translation(-padding, -padding);

  glUseProgram(m_program.id());
  glUniform2f(m_surfaceSizeLocation, surfaceWidth, surfaceHeight);
  glUniform2f(m_quadSizeLocation, quadWidth, quadHeight);
  glUniform2f(m_rectOriginLocation, rectOrigin, rectOrigin);
  glUniform2f(m_rectSizeLocation, width, height);
  glUniform4f(m_colorLocation, style.fill.r, style.fill.g, style.fill.b, style.fill.a);
  glUniform4f(m_fillEndColorLocation, style.fillEnd.r, style.fillEnd.g, style.fillEnd.b, style.fillEnd.a);
  glUniform4f(m_borderColorLocation, style.border.r, style.border.g, style.border.b, style.border.a);
  int fillMode = 0;
  if (style.fillMode == FillMode::Solid) {
    fillMode = 1;
  } else if (style.fillMode == FillMode::LinearGradient) {
    fillMode = 2;
  }
  glUniform1i(m_fillModeLocation, fillMode);
  glUniform2f(m_gradientDirectionLocation, style.gradientDirection == GradientDirection::Horizontal ? 1.0f : 0.0f,
              style.gradientDirection == GradientDirection::Vertical ? 1.0f : 0.0f);
  glUniform4f(m_radiiLocation, style.radius.tl, style.radius.tr, style.radius.br, style.radius.bl);
  glUniform1f(m_softnessLocation, style.softness);
  glUniform1f(m_borderWidthLocation, style.borderWidth);
  glUniformMatrix3fv(m_transformLocation, 1, GL_FALSE, quadTransform.m.data());
  glVertexAttribPointer(m_positionLocation, 2, GL_FLOAT, GL_FALSE, 0, vertices.data());
  glEnableVertexAttribArray(m_positionLocation);
  glDrawArrays(GL_TRIANGLES, 0, 6);
  glDisableVertexAttribArray(m_positionLocation);
}
