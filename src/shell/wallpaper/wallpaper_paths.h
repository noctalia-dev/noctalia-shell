#pragma once

#include "config/config_types.h"

#include <string>

struct WaylandOutput;

namespace wallpaper {

  [[nodiscard]] const WallpaperMonitorOverride*
  findWallpaperMonitorOverride(const WallpaperConfig& config, const WaylandOutput& output);

  [[nodiscard]] std::string
  resolveWallpaperDirectory(const WallpaperConfig& config, const WaylandOutput& output, ThemeMode mode);

  [[nodiscard]] std::string resolveGlobalWallpaperDirectory(const WallpaperConfig& config, ThemeMode mode);

} // namespace wallpaper
