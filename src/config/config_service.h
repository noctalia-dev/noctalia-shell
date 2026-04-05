#pragma once

#include "ui/style.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

struct WaylandOutput;

struct BarMonitorOverride {
  std::string match;
  std::optional<bool> enabled;
  std::optional<std::int32_t> height;
  std::optional<std::int32_t> paddingH;      // horizontal padding from bar edges to start/end sections
  std::optional<std::int32_t> widgetSpacing; // gap between widgets within a section
  std::optional<std::vector<std::string>> startWidgets;
  std::optional<std::vector<std::string>> centerWidgets;
  std::optional<std::vector<std::string>> endWidgets;
};

struct BarConfig {
  std::string name = "default";
  std::string position = "top";
  bool enabled = true;
  std::int32_t height = Style::barHeightDefault;
  std::int32_t radius = Style::radiusXl;
  std::int32_t marginH = 12;      // horizontal compositor margin (left = right = marginH)
  std::int32_t marginV = 6;       // vertical compositor margin (gap between bar and screen edge)
  std::int32_t paddingH = 16;     // horizontal padding from bar edges to start/end sections
  std::int32_t widgetSpacing = 8; // gap between widgets within a section
  std::int32_t shadowSize = 16;   // shadow depth in pixels (0 = no shadow)
  std::vector<std::string> startWidgets = {};
  std::vector<std::string> centerWidgets = {"workspaces"};
  std::vector<std::string> endWidgets = {"test", "tray", "notifications", "volume", "clock"};
  std::vector<BarMonitorOverride> monitorOverrides;
};

struct ClockConfig {
  std::string format = "{:%H:%M}";
};

enum class WallpaperFillMode : std::uint8_t {
  Center = 0,
  Crop = 1,
  Fit = 2,
  Stretch = 3,
  Repeat = 4,
};

enum class WallpaperTransition : std::uint8_t {
  Fade = 0,
  Wipe = 1,
  Disc = 2,
  Stripes = 3,
  Pixelate = 4,
  Honeycomb = 5,
};

struct WallpaperConfig {
  bool enabled = true;
  WallpaperFillMode fillMode = WallpaperFillMode::Crop;
  WallpaperTransition transition = WallpaperTransition::Fade;
  float transitionDurationMs = 1500.0f;
  float edgeSmoothness = 0.5f;
};

struct Config {
  std::vector<BarConfig> bars;
  ClockConfig clock;
  WallpaperConfig wallpaper;
};

class ConfigService {
public:
  using ReloadCallback = std::function<void()>;

  ConfigService();
  ~ConfigService();

  ConfigService(const ConfigService&) = delete;
  ConfigService& operator=(const ConfigService&) = delete;

  [[nodiscard]] const Config& config() const noexcept { return m_config; }
  [[nodiscard]] int watchFd() const noexcept { return m_inotifyFd; }

  void setReloadCallback(ReloadCallback callback);
  void checkReload();

  [[nodiscard]] static BarConfig resolveForOutput(const BarConfig& base, const WaylandOutput& output);

private:
  void loadFromFile(const std::string& path);
  void setupWatch();

  Config m_config;
  std::string m_configPath;
  int m_inotifyFd = -1;
  int m_watchFd = -1;
  bool m_pendingReload = false;
  ReloadCallback m_reloadCallback;
};
