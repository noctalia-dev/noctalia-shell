#pragma once

#include "render/core/color.h"
#include "render/core/mat3.h"
#include "render/core/shader_program.h"

#include <GLES2/gl2.h>

struct GraphStyle {
  Color lineColor1{};
  float count1 = 0.0f;
  float scroll1 = 1.0f;

  Color lineColor2{};
  float count2 = 0.0f;
  float scroll2 = 1.0f;

  float lineWidth = 1.5f;
  float graphFillOpacity = 0.15f;
  float aaSize = 0.5f;
};

class GraphProgram {
public:
  GraphProgram() = default;
  ~GraphProgram() = default;

  GraphProgram(const GraphProgram&) = delete;
  GraphProgram& operator=(const GraphProgram&) = delete;

  void ensureInitialized();
  void destroy();

  void draw(GLuint dataTexture, int texWidth, float surfaceWidth, float surfaceHeight, float width, float height,
            const GraphStyle& style, const Mat3& transform = Mat3::identity()) const;

private:
  ShaderProgram m_program;
  GLint m_positionLoc = -1;
  GLint m_surfaceSizeLoc = -1;
  GLint m_quadSizeLoc = -1;
  GLint m_transformLoc = -1;
  GLint m_lineColor1Loc = -1;
  GLint m_lineColor2Loc = -1;
  GLint m_count1Loc = -1;
  GLint m_count2Loc = -1;
  GLint m_scroll1Loc = -1;
  GLint m_scroll2Loc = -1;
  GLint m_lineWidthLoc = -1;
  GLint m_graphFillOpacityLoc = -1;
  GLint m_texWidthLoc = -1;
  GLint m_resXLoc = -1;
  GLint m_resYLoc = -1;
  GLint m_aaSizeLoc = -1;
  GLint m_dataSourceLoc = -1;
};
