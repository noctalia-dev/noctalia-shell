#pragma once

#include "render/Color.hpp"
#include "render/ShaderProgram.hpp"

#include <GLES2/gl2.h>

class TextProgram {
public:
    TextProgram() = default;
    ~TextProgram() = default;

    TextProgram(const TextProgram&) = delete;
    TextProgram& operator=(const TextProgram&) = delete;

    void ensureInitialized();
    void destroy();

    void draw(GLuint texture,
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
              const Color& color) const;

private:
    ShaderProgram m_program;
    GLint m_positionLocation = -1;
    GLint m_texCoordLocation = -1;
    GLint m_surfaceSizeLocation = -1;
    GLint m_rectLocation = -1;
    GLint m_colorLocation = -1;
    GLint m_samplerLocation = -1;
};
