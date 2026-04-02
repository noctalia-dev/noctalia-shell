#pragma once

#if NOCTALIA_HAVE_EGL
#include <GLES2/gl2.h>
#endif

class ShaderProgram {
public:
    ShaderProgram() = default;
    ~ShaderProgram();

    ShaderProgram(const ShaderProgram&) = delete;
    ShaderProgram& operator=(const ShaderProgram&) = delete;

    ShaderProgram(ShaderProgram&& other) noexcept;
    ShaderProgram& operator=(ShaderProgram&& other) noexcept;

    void create(const char* vertexSource, const char* fragmentSource);
    void destroy();

    [[nodiscard]] bool isValid() const noexcept;
    [[nodiscard]] GLuint id() const noexcept;

private:
    GLuint m_program = 0;
};
