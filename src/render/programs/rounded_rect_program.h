#pragma once

#include "render/core/color.h"
#include "render/core/shader_program.h"

#include <GLES2/gl2.h>

enum class FillMode {
  Solid,
  LinearGradient,
};

enum class GradientDirection {
  Horizontal,
  Vertical,
};

struct RoundedRectStyle {
  Color fill{};
  Color fillEnd{};
  Color border{};
  FillMode fillMode = FillMode::Solid;
  GradientDirection gradientDirection = GradientDirection::Horizontal;
  float radius = 0.0f;
  float softness = 1.0f;
  float borderWidth = 0.0f;
};

class RoundedRectProgram {
public:
  RoundedRectProgram() = default;
  ~RoundedRectProgram() = default;

  RoundedRectProgram(const RoundedRectProgram&) = delete;
  RoundedRectProgram& operator=(const RoundedRectProgram&) = delete;

  void ensureInitialized();
  void destroy();

  void draw(float surfaceWidth, float surfaceHeight, float x, float y, float width, float height,
            const RoundedRectStyle& style, float rotation = 0.0f, float scale = 1.0f) const;

private:
  ShaderProgram m_program;
  GLint m_positionLocation = -1;
  GLint m_surfaceSizeLocation = -1;
  GLint m_quadRectLocation = -1;
  GLint m_rectLocation = -1;
  GLint m_colorLocation = -1;
  GLint m_fillEndColorLocation = -1;
  GLint m_borderColorLocation = -1;
  GLint m_fillModeLocation = -1;
  GLint m_gradientDirectionLocation = -1;
  GLint m_radiusLocation = -1;
  GLint m_softnessLocation = -1;
  GLint m_borderWidthLocation = -1;
  GLint m_rotationLocation = -1;
  GLint m_scaleLocation = -1;
};
