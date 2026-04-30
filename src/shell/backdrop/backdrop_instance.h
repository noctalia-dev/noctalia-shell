#pragma once

#include "render/core/texture_manager.h"

#include <cstdint>
#include <memory>
#include <string>

struct wl_output;
class BackdropSurface;

struct BackdropInstance {
  std::uint32_t outputName = 0;
  struct wl_output* output = nullptr;
  std::int32_t scale = 1;
  std::string connectorName;

  std::unique_ptr<BackdropSurface> surface;

  std::string currentPath;
  TextureHandle currentTexture;
};
