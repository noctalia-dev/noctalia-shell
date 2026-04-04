#pragma once

#include "render/core/Color.h"
#include "render/core/ShaderProgram.h"

#include <GLES2/gl2.h>

class MsdfTextProgram {
public:
  MsdfTextProgram() = default;
  ~MsdfTextProgram() = default;

  MsdfTextProgram(const MsdfTextProgram&) = delete;
  MsdfTextProgram& operator=(const MsdfTextProgram&) = delete;

  void ensureInitialized();
  void destroy();

  void draw(GLuint texture, float surfaceWidth, float surfaceHeight, float x, float y, float width, float height,
            float u0, float v0, float u1, float v1, float pxRange, const Color& color) const;

private:
  ShaderProgram m_program;
  GLint m_positionLocation = -1;
  GLint m_texCoordLocation = -1;
  GLint m_surfaceSizeLocation = -1;
  GLint m_rectLocation = -1;
  GLint m_pxRangeLocation = -1;
  GLint m_colorLocation = -1;
  GLint m_samplerLocation = -1;
};
