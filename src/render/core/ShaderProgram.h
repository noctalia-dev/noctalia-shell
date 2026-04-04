#pragma once

#include <GLES2/gl2.h>

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
