#pragma once

#include <cstdint>

struct wl_output;
struct wl_surface;

struct AttachedPanelParentContext {
  wl_surface* parentSurface = nullptr;
  wl_output* output = nullptr;
  std::int32_t barX = 0;
  std::int32_t barY = 0;
  std::int32_t barWidth = 0;
  std::int32_t barHeight = 0;
  std::uint32_t parentWidth = 0;
  std::uint32_t parentHeight = 0;
};

struct AttachedPanelGeometry {
  float x = 0.0f;
  float y = 0.0f;
  float width = 0.0f;
  float height = 0.0f;
  float cornerRadius = 0.0f;
};
