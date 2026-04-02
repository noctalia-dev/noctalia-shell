#include "render/RoundedRectProgram.hpp"

#include <array>
#include <stdexcept>

namespace {

constexpr char kVertexShaderSource[] = R"(
precision mediump float;

attribute vec2 a_position;
uniform vec2 u_surface_size;
uniform vec4 u_rect;
varying vec2 v_local;

vec2 to_ndc(vec2 pixel_pos) {
    vec2 normalized = pixel_pos / u_surface_size;
    return vec2(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0);
}

void main() {
    vec2 pixel_pos = u_rect.xy + (a_position * u_rect.zw);
    v_local = a_position * u_rect.zw;
    gl_Position = vec4(to_ndc(pixel_pos), 0.0, 1.0);
}
)";

constexpr char kFragmentShaderSource[] = R"(
precision mediump float;

uniform vec4 u_rect;
uniform vec4 u_color;
uniform float u_radius;
uniform float u_softness;
varying vec2 v_local;

float rounded_rect_alpha(vec2 point, vec2 size, float radius) {
    vec2 half_size = size * 0.5;
    vec2 centered = point - half_size;
    vec2 q = abs(centered) - (half_size - vec2(radius));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main() {
    float distance = rounded_rect_alpha(v_local, u_rect.zw, u_radius);
    float alpha = 1.0 - smoothstep(0.0, u_softness, distance);
    gl_FragColor = vec4(u_color.rgb, u_color.a * alpha);
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
    m_rectLocation = glGetUniformLocation(m_program.id(), "u_rect");
    m_colorLocation = glGetUniformLocation(m_program.id(), "u_color");
    m_radiusLocation = glGetUniformLocation(m_program.id(), "u_radius");
    m_softnessLocation = glGetUniformLocation(m_program.id(), "u_softness");

    if (m_positionLocation < 0 ||
        m_surfaceSizeLocation < 0 ||
        m_rectLocation < 0 ||
        m_colorLocation < 0 ||
        m_radiusLocation < 0 ||
        m_softnessLocation < 0) {
        throw std::runtime_error("failed to query rounded-rect shader locations");
    }
}

void RoundedRectProgram::destroy() {
    m_program.destroy();
    m_positionLocation = -1;
    m_surfaceSizeLocation = -1;
    m_rectLocation = -1;
    m_colorLocation = -1;
    m_radiusLocation = -1;
    m_softnessLocation = -1;
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

    glUseProgram(m_program.id());
    glUniform2f(m_surfaceSizeLocation, surfaceWidth, surfaceHeight);
    glUniform4f(m_rectLocation, x, y, width, height);
    glUniform4f(m_colorLocation, style.red, style.green, style.blue, style.alpha);
    glUniform1f(m_radiusLocation, style.radius);
    glUniform1f(m_softnessLocation, style.softness);
    glVertexAttribPointer(m_positionLocation, 2, GL_FLOAT, GL_FALSE, 0, vertices.data());
    glEnableVertexAttribArray(m_positionLocation);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(m_positionLocation);
}
