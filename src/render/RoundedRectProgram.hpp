#pragma once

#include "render/ShaderProgram.hpp"

#if NOCTALIA_HAVE_EGL
#include <GLES2/gl2.h>
#endif

struct RoundedRectStyle {
    float red = 0.0f;
    float green = 0.0f;
    float blue = 0.0f;
    float alpha = 1.0f;
    float radius = 0.0f;
    float softness = 1.0f;
};

class RoundedRectProgram {
public:
    RoundedRectProgram() = default;
    ~RoundedRectProgram() = default;

    RoundedRectProgram(const RoundedRectProgram&) = delete;
    RoundedRectProgram& operator=(const RoundedRectProgram&) = delete;

    void ensureInitialized();
    void destroy();

    void draw(float surfaceWidth,
              float surfaceHeight,
              float x,
              float y,
              float width,
              float height,
              const RoundedRectStyle& style) const;

private:
    ShaderProgram m_program;
#if NOCTALIA_HAVE_EGL
    GLint m_positionLocation = -1;
    GLint m_surfaceSizeLocation = -1;
    GLint m_rectLocation = -1;
    GLint m_colorLocation = -1;
    GLint m_radiusLocation = -1;
    GLint m_softnessLocation = -1;
#endif
};
