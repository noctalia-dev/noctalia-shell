#pragma once

#include "render/core/Color.h"
#include "render/core/ShaderProgram.h"

#include <GLES2/gl2.h>

struct SpinnerStyle {
  Color color{};
  float thickness = 2.0f;
  float angle = 0.0f;
};

class SpinnerProgram {
public:
  SpinnerProgram() = default;
  ~SpinnerProgram() = default;

  SpinnerProgram(const SpinnerProgram&) = delete;
  SpinnerProgram& operator=(const SpinnerProgram&) = delete;

  void ensureInitialized();
  void destroy();

  void draw(float surfaceWidth, float surfaceHeight, float x, float y, float width, float height,
            const SpinnerStyle& style) const;

private:
  ShaderProgram m_program;
  GLint m_positionLocation = -1;
  GLint m_surfaceSizeLocation = -1;
  GLint m_quadRectLocation = -1;
  GLint m_rectLocation = -1;
  GLint m_colorLocation = -1;
  GLint m_thicknessLocation = -1;
  GLint m_angleLocation = -1;
};
