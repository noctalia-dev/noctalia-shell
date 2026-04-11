#pragma once

#include "render/core/color.h"
#include "render/core/mat3.h"
#include "render/core/shader_program.h"

#include <GLES2/gl2.h>

enum class FillMode {
  None,
  Solid,
  LinearGradient,
};

enum class GradientDirection {
  Horizontal,
  Vertical,
};

// Per-corner radii: top-left, top-right, bottom-right, bottom-left.
// Implicit construction from a single float sets all four corners uniformly,
// so existing `.radius = value` assignments continue to compile unchanged.
struct Radii {
  float tl = 0.0f;
  float tr = 0.0f;
  float br = 0.0f;
  float bl = 0.0f;

  Radii() = default;
  /* implicit */ Radii(float r) : tl(r), tr(r), br(r), bl(r) {} // NOLINT(google-explicit-constructor)
  Radii(float tlv, float trv, float brv, float blv) : tl(tlv), tr(trv), br(brv), bl(blv) {}
};

struct RoundedRectStyle {
  Color fill{};
  Color fillEnd{};
  Color border{};
  FillMode fillMode = FillMode::Solid;
  GradientDirection gradientDirection = GradientDirection::Horizontal;
  Radii radius{};
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

  void draw(float surfaceWidth, float surfaceHeight, float width, float height, const RoundedRectStyle& style,
            const Mat3& transform = Mat3::identity()) const;

private:
  ShaderProgram m_program;
  GLint m_positionLocation = -1;
  GLint m_surfaceSizeLocation = -1;
  GLint m_quadSizeLocation = -1;
  GLint m_rectOriginLocation = -1;
  GLint m_rectSizeLocation = -1;
  GLint m_colorLocation = -1;
  GLint m_fillEndColorLocation = -1;
  GLint m_borderColorLocation = -1;
  GLint m_fillModeLocation = -1;
  GLint m_gradientDirectionLocation = -1;
  GLint m_radiiLocation = -1;
  GLint m_softnessLocation = -1;
  GLint m_borderWidthLocation = -1;
  GLint m_transformLocation = -1;
};
