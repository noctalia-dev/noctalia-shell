#pragma once

#include <cstdint>

enum class WallpaperSourceKind : std::uint8_t {
  Image = 0,
  Color = 1,
};

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
