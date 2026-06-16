#pragma once

#include "config/config_types.h"

#include <string>
#include <string_view>

struct WaylandOutput;

namespace wallpaper {

  inline constexpr std::string_view kDefaultWallpaperDirectory = "~/Pictures/Wallpapers";

  [[nodiscard]] const WallpaperMonitorOverride*
  findWallpaperMonitorOverride(const WallpaperConfig& config, const WaylandOutput& output);

  [[nodiscard]] std::string
  resolveWallpaperDirectory(const WallpaperConfig& config, const WaylandOutput& output, ThemeMode mode);

  [[nodiscard]] std::string resolveGlobalWallpaperDirectory(const WallpaperConfig& config, ThemeMode mode);

} // namespace wallpaper
