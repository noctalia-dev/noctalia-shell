#pragma once

#include "render/core/mat3.h"
#include "render/core/shader_program.h"

#include <GLES2/gl2.h>

// Renders a pre-rasterized premultiplied-RGBA glyph quad.
// Used for all text and icons rendered via Pango/Cairo or direct FT/Cairo.
class ColorGlyphProgram {
public:
  ColorGlyphProgram() = default;
  ~ColorGlyphProgram() = default;

  ColorGlyphProgram(const ColorGlyphProgram&) = delete;
  ColorGlyphProgram& operator=(const ColorGlyphProgram&) = delete;

  void ensureInitialized();
  void destroy();

  void draw(GLuint texture, float surfaceWidth, float surfaceHeight, float width, float height, float u0, float v0,
            float u1, float v1, float opacity, const Mat3& transform = Mat3::identity()) const;

private:
  ShaderProgram m_program;
  GLint m_positionLocation = -1;
  GLint m_texCoordLocation = -1;
  GLint m_surfaceSizeLocation = -1;
  GLint m_rectLocation = -1;
  GLint m_opacityLocation = -1;
  GLint m_samplerLocation = -1;
  GLint m_transformLocation = -1;
};
