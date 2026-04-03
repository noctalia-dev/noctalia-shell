#include "render/MsdfTextProgram.hpp"

#include <array>
#include <stdexcept>

namespace {

constexpr char kVertexShaderSource[] = R"(
precision highp float;

attribute vec2 a_position;
attribute vec2 a_texcoord;
uniform vec2 u_surface_size;
uniform vec4 u_rect;
varying vec2 v_texcoord;

vec2 to_ndc(vec2 pixel_pos) {
    vec2 normalized = pixel_pos / u_surface_size;
    return vec2(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0);
}

void main() {
    vec2 pixel_pos = u_rect.xy + (a_position * u_rect.zw);
    v_texcoord = a_texcoord;
    gl_Position = vec4(to_ndc(pixel_pos), 0.0, 1.0);
}
)";

constexpr char kFragmentShaderSource[] = R"(
precision highp float;

uniform sampler2D u_texture;
uniform vec4 u_color;
uniform float u_px_range;
varying vec2 v_texcoord;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    vec3 msd = texture2D(u_texture, v_texcoord).rgb;
    float sd = median(msd.r, msd.g, msd.b);
    float screenPxDist = u_px_range * (sd - 0.5);
    float opacity = clamp(screenPxDist + 0.5, 0.0, 1.0);
    gl_FragColor = vec4(u_color.rgb, u_color.a * opacity);
}
)";

} // namespace

void MsdfTextProgram::ensureInitialized() {
    if (m_program.isValid()) {
        return;
    }

    m_program.create(kVertexShaderSource, kFragmentShaderSource);
    m_positionLocation = glGetAttribLocation(m_program.id(), "a_position");
    m_texCoordLocation = glGetAttribLocation(m_program.id(), "a_texcoord");
    m_surfaceSizeLocation = glGetUniformLocation(m_program.id(), "u_surface_size");
    m_rectLocation = glGetUniformLocation(m_program.id(), "u_rect");
    m_pxRangeLocation = glGetUniformLocation(m_program.id(), "u_px_range");
    m_colorLocation = glGetUniformLocation(m_program.id(), "u_color");
    m_samplerLocation = glGetUniformLocation(m_program.id(), "u_texture");

    if (m_positionLocation < 0 ||
        m_texCoordLocation < 0 ||
        m_surfaceSizeLocation < 0 ||
        m_rectLocation < 0 ||
        m_pxRangeLocation < 0 ||
        m_colorLocation < 0 ||
        m_samplerLocation < 0) {
        throw std::runtime_error("failed to query MSDF text shader locations");
    }
}

void MsdfTextProgram::destroy() {
    m_program.destroy();
    m_positionLocation = -1;
    m_texCoordLocation = -1;
    m_surfaceSizeLocation = -1;
    m_rectLocation = -1;
    m_pxRangeLocation = -1;
    m_colorLocation = -1;
    m_samplerLocation = -1;
}

void MsdfTextProgram::draw(GLuint texture,
                           float surfaceWidth,
                           float surfaceHeight,
                           float x,
                           float y,
                           float width,
                           float height,
                           float u0,
                           float v0,
                           float u1,
                           float v1,
                           float pxRange,
                           const Color& color) const {
    if (!m_program.isValid() || texture == 0 || width <= 0.0f || height <= 0.0f) {
        return;
    }

    const std::array<GLfloat, 12> positions = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        0.0f, 1.0f,
        1.0f, 0.0f,
        1.0f, 1.0f,
    };

    const std::array<GLfloat, 12> texcoords = {
        u0, v0,
        u1, v0,
        u0, v1,
        u0, v1,
        u1, v0,
        u1, v1,
    };

    glUseProgram(m_program.id());
    glUniform2f(m_surfaceSizeLocation, surfaceWidth, surfaceHeight);
    glUniform4f(m_rectLocation, x, y, width, height);
    glUniform1f(m_pxRangeLocation, pxRange);
    glUniform4f(m_colorLocation, color.r, color.g, color.b, color.a);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glUniform1i(m_samplerLocation, 0);
    const auto posAttr = static_cast<GLuint>(m_positionLocation);
    const auto texAttr = static_cast<GLuint>(m_texCoordLocation);
    glVertexAttribPointer(posAttr, 2, GL_FLOAT, GL_FALSE, 0, positions.data());
    glVertexAttribPointer(texAttr, 2, GL_FLOAT, GL_FALSE, 0, texcoords.data());
    glEnableVertexAttribArray(posAttr);
    glEnableVertexAttribArray(texAttr);
    glDrawArrays(GL_TRIANGLES, 0, 6);
    glDisableVertexAttribArray(posAttr);
    glDisableVertexAttribArray(texAttr);
}
