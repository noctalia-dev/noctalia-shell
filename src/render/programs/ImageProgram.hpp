#pragma once

#include "render/core/Color.hpp"
#include "render/core/ShaderProgram.hpp"

#include <GLES2/gl2.h>

class ImageProgram {
public:
    ImageProgram() = default;
    ~ImageProgram() = default;

    ImageProgram(const ImageProgram&) = delete;
    ImageProgram& operator=(const ImageProgram&) = delete;

    void ensureInitialized();
    void destroy();

    void draw(GLuint texture,
              float surfaceWidth,
              float surfaceHeight,
              float x,
              float y,
              float width,
              float height,
              const Color& tint,
              float opacity) const;

private:
    ShaderProgram m_program;
    GLint m_positionLocation = -1;
    GLint m_texCoordLocation = -1;
    GLint m_surfaceSizeLocation = -1;
    GLint m_rectLocation = -1;
    GLint m_tintLocation = -1;
    GLint m_opacityLocation = -1;
    GLint m_samplerLocation = -1;
};
