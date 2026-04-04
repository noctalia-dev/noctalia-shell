#include "render/programs/RoundedRectProgram.hpp"

#include <array>
#include <stdexcept>

namespace {

constexpr char kVertexShaderSource[] = R"(
precision highp float;

attribute vec2 a_position;
uniform vec2 u_surface_size;
uniform vec4 u_quad_rect;
uniform vec4 u_rect;
varying vec2 v_pixel;

vec2 to_ndc(vec2 pixel_pos) {
    vec2 normalized = pixel_pos / u_surface_size;
    return vec2(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0);
}

void main() {
    vec2 pixel_pos = u_quad_rect.xy + (a_position * u_quad_rect.zw);
    v_pixel = pixel_pos;
    gl_Position = vec4(to_ndc(pixel_pos), 0.0, 1.0);
}
)";

constexpr char kFragmentShaderSource[] = R"(
precision highp float;

uniform vec4 u_rect;
uniform vec4 u_color;
uniform vec4 u_fill_end_color;
uniform vec4 u_border_color;
uniform int u_fill_mode;
uniform vec2 u_gradient_direction;
uniform float u_radius;
uniform float u_softness;
uniform float u_border_width;
varying vec2 v_pixel;

float rounded_rect_distance(vec2 point, vec2 size, float radius) {
    vec2 half_size = size * 0.5;
    vec2 centered = point - half_size;
    vec2 q = abs(centered) - (half_size - vec2(radius));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    float aa = max(u_softness, 0.85);
    vec2 local_point = v_pixel - u_rect.xy;
    vec2 uv = clamp(local_point / u_rect.zw, vec2(0.0), vec2(1.0));

    float outer_distance = rounded_rect_distance(local_point, u_rect.zw, u_radius);
    float outer_coverage = 1.0 - smoothstep(-aa, aa, outer_distance);

    float inner_radius = max(u_radius - u_border_width, 0.0);
    vec2 inner_size = max(u_rect.zw - vec2(u_border_width * 2.0), vec2(0.0));
    vec2 inner_point = local_point - vec2(u_border_width);
    float inner_distance = rounded_rect_distance(inner_point, inner_size, inner_radius);
    float inner_coverage = 1.0 - smoothstep(-aa, aa, inner_distance);

    float gradient_t = clamp(dot(uv, u_gradient_direction), 0.0, 1.0);
    vec4 fill_base = (u_fill_mode == 0) ? u_color : mix(u_color, u_fill_end_color, gradient_t);
    float fill_alpha = fill_base.a * inner_coverage;
    float border_coverage = max(outer_coverage - inner_coverage, 0.0);
    float border_alpha = u_border_color.a * border_coverage;

    float out_alpha = fill_alpha + border_alpha * (1.0 - fill_alpha);
    if (out_alpha <= 0.0) {
        discard;
    }

    vec3 composite_rgb =
        (fill_base.rgb * fill_alpha + u_border_color.rgb * border_alpha * (1.0 - fill_alpha)) /
        out_alpha;
    gl_FragColor = vec4(composite_rgb, out_alpha);
}
)";

} // namespace

void RoundedRectProgram::ensureInitialized() {
    if (m_program.isValid()) {
        return;
    }

    m_program.create(kVertexShaderSource, kFragmentShaderSource);
    m_positionLocation = glGetAttribLocation(m_program.id(), "a_position");
    m_surfaceSizeLocation = glGetUniformLocation(m_program.id(), "u_surface_size");
    m_quadRectLocation = glGetUniformLocation(m_program.id(), "u_quad_rect");
    m_rectLocation = glGetUniformLocation(m_program.id(), "u_rect");
    m_colorLocation = glGetUniformLocation(m_program.id(), "u_color");
    m_fillEndColorLocation = glGetUniformLocation(m_program.id(), "u_fill_end_color");
    m_borderColorLocation = glGetUniformLocation(m_program.id(), "u_border_color");
    m_fillModeLocation = glGetUniformLocation(m_program.id(), "u_fill_mode");
    m_gradientDirectionLocation = glGetUniformLocation(m_program.id(), "u_gradient_direction");
    m_radiusLocation = glGetUniformLocation(m_program.id(), "u_radius");
    m_softnessLocation = glGetUniformLocation(m_program.id(), "u_softness");
    m_borderWidthLocation = glGetUniformLocation(m_program.id(), "u_border_width");

    if (m_positionLocation < 0 ||
        m_surfaceSizeLocation < 0 ||
        m_quadRectLocation < 0 ||
        m_rectLocation < 0 ||
        m_colorLocation < 0 ||
        m_fillEndColorLocation < 0 ||
        m_borderColorLocation < 0 ||
        m_fillModeLocation < 0 ||
        m_gradientDirectionLocation < 0 ||
        m_radiusLocation < 0 ||
        m_softnessLocation < 0 ||
        m_borderWidthLocation < 0) {
        throw std::runtime_error("failed to query rounded-rect shader locations");
    }
}

void RoundedRectProgram::destroy() {
    m_program.destroy();
    m_positionLocation = -1;
    m_surfaceSizeLocation = -1;
    m_quadRectLocation = -1;
    m_rectLocation = -1;
    m_colorLocation = -1;
    m_fillEndColorLocation = -1;
    m_borderColorLocation = -1;
    m_fillModeLocation = -1;
    m_gradientDirectionLocation = -1;
    m_radiusLocation = -1;
    m_softnessLocation = -1;
    m_borderWidthLocation = -1;
}

void RoundedRectProgram::draw(float surfaceWidth,
                              float surfaceHeight,
                              float x,
                              float y,
                              float width,
                              float height,
                              const RoundedRectStyle& style) const {
    if (!m_program.isValid() || width <= 0.0f || height <= 0.0f) {
        return;
    }

    const std::array<GLfloat, 12> vertices = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
    };

    const float padding = std::max(style.borderWidth + style.softness + 2.0f, 2.0f);
    const float quadX = x - padding;
    const float quadY = y - padding;
    const float quadWidth = width + padding * 2.0f;
    const float quadHeight = height + padding * 2.0f;

    glUseProgram(m_program.id());
    glUniform2f(m_surfaceSizeLocation, surfaceWidth, surfaceHeight);
    glUniform4f(m_quadRectLocation, quadX, quadY, quadWidth, quadHeight);
    glUniform4f(m_rectLocation, x, y, width, height);
    glUniform4f(m_colorLocation, style.fill.r, style.fill.g, style.fill.b, style.fill.a);
    glUniform4f(m_fillEndColorLocation,
                style.fillEnd.r,
                style.fillEnd.g,
                style.fillEnd.b,
                style.fillEnd.a);
    glUniform4f(m_borderColorLocation,
                style.border.r,
                style.border.g,
                style.border.b,
                style.border.a);
    glUniform1i(m_fillModeLocation, style.fillMode == FillMode::Solid ? 0 : 1);
    glUniform2f(m_gradientDirectionLocation,
                style.gradientDirection == GradientDirection::Horizontal ? 1.0f : 0.0f,
                style.gradientDirection == GradientDirection::Vertical ? 1.0f : 0.0f);
    glUniform1f(m_radiusLocation, style.radius);
    glUniform1f(m_softnessLocation, style.softness);
    glUniform1f(m_borderWidthLocation, style.borderWidth);
    glVertexAttribPointer(m_positionLocation, 2, GL_FLOAT, GL_FALSE, 0, vertices.data());
    glEnableVertexAttribArray(m_positionLocation);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(m_positionLocation);
}
