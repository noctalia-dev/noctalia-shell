#include "render/programs/image_program.h"

#include <array>
#include <stdexcept>

namespace {

constexpr char kVertexShaderSource[] = R"(
precision highp float;

attribute vec2 a_position;
attribute vec2 a_texcoord;
uniform vec2 u_surface_size;
uniform vec4 u_rect;
uniform float u_rotation;
uniform float u_scale;
varying vec2 v_texcoord;

vec2 to_ndc(vec2 pixel_pos) {
    vec2 normalized = pixel_pos / u_surface_size;
    return vec2(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0);
}

void main() {
    vec2 local = a_position * u_rect.zw;
    vec2 center = u_rect.zw * 0.5;
    vec2 offset = (local - center) * u_scale;
    float cs = cos(u_rotation);
    float sn = sin(u_rotation);
    vec2 rotated = vec2(offset.x * cs - offset.y * sn,
                        offset.x * sn + offset.y * cs);
    vec2 pixel_pos = u_rect.xy + center + rotated;
    v_texcoord = a_texcoord;
    gl_Position = vec4(to_ndc(pixel_pos), 0.0, 1.0);
}
)";

constexpr char kFragmentShaderSource[] = R"(
precision mediump float;

uniform sampler2D u_texture;
uniform vec4 u_tint;
uniform float u_opacity;
varying vec2 v_texcoord;

void main() {
    vec4 texel = texture2D(u_texture, v_texcoord);
    vec4 color = texel * u_tint * vec4(1.0, 1.0, 1.0, u_opacity);
    gl_FragColor = vec4(color.rgb * color.a, color.a);
}
)";

} // namespace

void ImageProgram::ensureInitialized() {
  if (m_program.isValid()) {
    return;
  }

  m_program.create(kVertexShaderSource, kFragmentShaderSource);
  m_positionLocation = glGetAttribLocation(m_program.id(), "a_position");
  m_texCoordLocation = glGetAttribLocation(m_program.id(), "a_texcoord");
  m_surfaceSizeLocation = glGetUniformLocation(m_program.id(), "u_surface_size");
  m_rectLocation = glGetUniformLocation(m_program.id(), "u_rect");
  m_tintLocation = glGetUniformLocation(m_program.id(), "u_tint");
  m_opacityLocation = glGetUniformLocation(m_program.id(), "u_opacity");
  m_samplerLocation = glGetUniformLocation(m_program.id(), "u_texture");
  m_rotationLocation = glGetUniformLocation(m_program.id(), "u_rotation");
  m_scaleLocation = glGetUniformLocation(m_program.id(), "u_scale");

  if (m_positionLocation < 0 || m_texCoordLocation < 0 || m_surfaceSizeLocation < 0 || m_rectLocation < 0 ||
      m_tintLocation < 0 || m_opacityLocation < 0 || m_samplerLocation < 0 ||
      m_rotationLocation < 0 || m_scaleLocation < 0) {
    throw std::runtime_error("failed to query image shader locations");
  }
}

void ImageProgram::destroy() {
  m_program.destroy();
  m_positionLocation = -1;
  m_texCoordLocation = -1;
  m_surfaceSizeLocation = -1;
  m_rectLocation = -1;
  m_tintLocation = -1;
  m_opacityLocation = -1;
  m_samplerLocation = -1;
  m_rotationLocation = -1;
  m_scaleLocation = -1;
}

void ImageProgram::draw(GLuint texture, float surfaceWidth, float surfaceHeight, float x, float y, float width,
                        float height, const Color& tint, float opacity, float rotation, float scale) const {
  if (!m_program.isValid() || texture == 0 || width <= 0.0f || height <= 0.0f) {
    return;
  }

  const std::array<GLfloat, 12> positions = {
      0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
  };

  const std::array<GLfloat, 12> texcoords = {
      0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 1.0f, 0.0f, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f,
  };

  glUseProgram(m_program.id());
  glUniform2f(m_surfaceSizeLocation, surfaceWidth, surfaceHeight);
  glUniform4f(m_rectLocation, x, y, width, height);
  glUniform4f(m_tintLocation, tint.r, tint.g, tint.b, tint.a);
  glUniform1f(m_opacityLocation, opacity);
  glUniform1f(m_rotationLocation, rotation);
  glUniform1f(m_scaleLocation, scale);
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
