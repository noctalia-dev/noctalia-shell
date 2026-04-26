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

enum class CornerShape {
  Convex,
  Concave,
};

struct CornerShapes {
  CornerShape tl = CornerShape::Convex;
  CornerShape tr = CornerShape::Convex;
  CornerShape br = CornerShape::Convex;
  CornerShape bl = CornerShape::Convex;
};

constexpr bool operator==(const CornerShapes& lhs, const CornerShapes& rhs) noexcept {
  return lhs.tl == rhs.tl && lhs.tr == rhs.tr && lhs.br == rhs.br && lhs.bl == rhs.bl;
}

struct RectInsets {
  float left = 0.0f;
  float top = 0.0f;
  float right = 0.0f;
  float bottom = 0.0f;
};

constexpr bool operator==(const RectInsets& lhs, const RectInsets& rhs) noexcept {
  return lhs.left == rhs.left && lhs.top == rhs.top && lhs.right == rhs.right && lhs.bottom == rhs.bottom;
}

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

constexpr bool operator==(const Radii& lhs, const Radii& rhs) noexcept {
  return lhs.tl == rhs.tl && lhs.tr == rhs.tr && lhs.br == rhs.br && lhs.bl == rhs.bl;
}

struct RoundedRectStyle {
  Color fill{};
  Color fillEnd{};
  Color border{};
  FillMode fillMode = FillMode::Solid;
  GradientDirection gradientDirection = GradientDirection::Horizontal;
  CornerShapes corners{};
  RectInsets logicalInset{};
  Radii radius{};
  float softness = 1.0f;
  float borderWidth = 0.0f;
  bool outerShadow = false;
  float shadowCutoutOffsetX = 0.0f;
  float shadowCutoutOffsetY = 0.0f;
  bool shadowExclusion = false;
  float shadowExclusionOffsetX = 0.0f;
  float shadowExclusionOffsetY = 0.0f;
  float shadowExclusionWidth = 0.0f;
  float shadowExclusionHeight = 0.0f;
  CornerShapes shadowExclusionCorners{};
  RectInsets shadowExclusionLogicalInset{};
  Radii shadowExclusionRadius{};
};

constexpr bool operator==(const RoundedRectStyle& lhs, const RoundedRectStyle& rhs) noexcept {
  return lhs.fill == rhs.fill && lhs.fillEnd == rhs.fillEnd && lhs.border == rhs.border &&
         lhs.fillMode == rhs.fillMode && lhs.gradientDirection == rhs.gradientDirection && lhs.corners == rhs.corners &&
         lhs.logicalInset == rhs.logicalInset && lhs.radius == rhs.radius && lhs.softness == rhs.softness &&
         lhs.borderWidth == rhs.borderWidth && lhs.outerShadow == rhs.outerShadow &&
         lhs.shadowCutoutOffsetX == rhs.shadowCutoutOffsetX && lhs.shadowCutoutOffsetY == rhs.shadowCutoutOffsetY &&
         lhs.shadowExclusion == rhs.shadowExclusion && lhs.shadowExclusionOffsetX == rhs.shadowExclusionOffsetX &&
         lhs.shadowExclusionOffsetY == rhs.shadowExclusionOffsetY &&
         lhs.shadowExclusionWidth == rhs.shadowExclusionWidth &&
         lhs.shadowExclusionHeight == rhs.shadowExclusionHeight &&
         lhs.shadowExclusionCorners == rhs.shadowExclusionCorners &&
         lhs.shadowExclusionLogicalInset == rhs.shadowExclusionLogicalInset &&
         lhs.shadowExclusionRadius == rhs.shadowExclusionRadius;
}

class RectProgram {
public:
  RectProgram() = default;
  ~RectProgram() = default;

  RectProgram(const RectProgram&) = delete;
  RectProgram& operator=(const RectProgram&) = delete;

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
  GLint m_cornerShapesLocation = -1;
  GLint m_logicalInsetLocation = -1;
  GLint m_radiiLocation = -1;
  GLint m_softnessLocation = -1;
  GLint m_borderWidthLocation = -1;
  GLint m_outerShadowLocation = -1;
  GLint m_shadowCutoutOffsetLocation = -1;
  GLint m_shadowExclusionLocation = -1;
  GLint m_shadowExclusionOffsetLocation = -1;
  GLint m_shadowExclusionSizeLocation = -1;
  GLint m_shadowExclusionCornerShapesLocation = -1;
  GLint m_shadowExclusionLogicalInsetLocation = -1;
  GLint m_shadowExclusionRadiiLocation = -1;
  GLint m_transformLocation = -1;
};
