#pragma once

#include "config/config_service.h"
#include "render/core/shader_program.h"

#include <GLES2/gl2.h>
#include <array>

struct TransitionParams {
  float direction = 0.0f;     // wipe: 0=left, 1=right, 2=up, 3=down
  float centerX = 0.5f;       // disc, honeycomb
  float centerY = 0.5f;       // disc, honeycomb
  float stripeCount = 12.0f;  // stripes
  float angle = 30.0f;        // stripes (degrees)
  float maxBlockSize = 64.0f; // pixelate
  float cellSize = 0.04f;     // honeycomb
  float smoothness = 0.5f;    // wipe, disc, stripes
  float aspectRatio = 1.777f; // disc, stripes, honeycomb (computed at render time)
};

class WallpaperProgram {
public:
  WallpaperProgram() = default;
  ~WallpaperProgram() = default;

  WallpaperProgram(const WallpaperProgram&) = delete;
  WallpaperProgram& operator=(const WallpaperProgram&) = delete;

  void ensureInitialized();
  void destroy();

  void draw(WallpaperTransition type, GLuint texture1, GLuint texture2, float surfaceWidth, float surfaceHeight,
            float imageWidth1, float imageHeight1, float imageWidth2, float imageHeight2, float progress,
            float fillMode, const TransitionParams& params) const;

private:
  static constexpr std::size_t kTransitionCount = 6;

  struct ProgramData {
    ShaderProgram program;
    GLint positionLoc = -1;
    GLint texCoordLoc = -1;
    // Samplers
    GLint source1Loc = -1;
    GLint source2Loc = -1;
    // Common uniforms
    GLint progressLoc = -1;
    GLint fillModeLoc = -1;
    GLint imageWidth1Loc = -1;
    GLint imageHeight1Loc = -1;
    GLint imageWidth2Loc = -1;
    GLint imageHeight2Loc = -1;
    GLint screenWidthLoc = -1;
    GLint screenHeightLoc = -1;
    GLint fillColorLoc = -1;
    // Per-transition uniforms
    GLint directionLoc = -1;
    GLint smoothnessLoc = -1;
    GLint centerXLoc = -1;
    GLint centerYLoc = -1;
    GLint aspectRatioLoc = -1;
    GLint stripeCountLoc = -1;
    GLint angleLoc = -1;
    GLint maxBlockSizeLoc = -1;
    GLint cellSizeLoc = -1;
  };

  void initProgram(std::size_t index, const char* fragSource);

  std::array<ProgramData, kTransitionCount> m_programs;
};
