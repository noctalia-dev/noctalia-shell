#pragma once

#include "ui/style.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>

struct WaylandOutput;

struct BarMonitorOverride {
  std::string match;
  std::optional<bool> enabled;
  std::optional<std::int32_t> height;
  std::optional<std::int32_t> paddingH;      // horizontal padding from bar edges to start/end sections
  std::optional<std::int32_t> widgetSpacing; // gap between widgets within a section
  std::optional<float> scale;
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
  std::int32_t marginH = 180;     // horizontal compositor margin (left = right = marginH)
  std::int32_t marginV = 10;      // vertical compositor margin (gap between bar and screen edge)
  std::int32_t paddingH = 14;     // horizontal padding from bar edges to start/end sections
  std::int32_t widgetSpacing = 6; // gap between widgets within a section
  std::int32_t shadowBlur = 12;   // shadow blur radius in pixels (0 = no shadow)
  std::int32_t shadowOffsetX = 0; // horizontal shadow offset in pixels
  std::int32_t shadowOffsetY = 6; // vertical shadow offset in pixels (positive = down)
  float scale = 1.0f;             // content scale multiplier for icons and text
  std::vector<std::string> startWidgets = {"cpu", "temp", "ram"};
  std::vector<std::string> centerWidgets = {"workspaces"};
  std::vector<std::string> endWidgets = {"test",    "tray",   "notifications", "volume",
                                         "battery", "spacer", "date",          "clock"};
  std::vector<BarMonitorOverride> monitorOverrides;
};

using WidgetSettingValue = std::variant<bool, std::int64_t, double, std::string>;

struct WidgetConfig {
  std::string type; // widget type (e.g. "clock", "spacer"); defaults to the entry name
  std::unordered_map<std::string, WidgetSettingValue> settings;

  [[nodiscard]] std::string getString(const std::string& key, const std::string& fallback = {}) const;
  [[nodiscard]] std::int64_t getInt(const std::string& key, std::int64_t fallback = 0) const;
  [[nodiscard]] double getDouble(const std::string& key, double fallback = 0.0) const;
  [[nodiscard]] bool getBool(const std::string& key, bool fallback = false) const;
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

struct WallpaperMonitorOverride {
  std::string match;
  std::optional<bool> enabled;
};

struct WallpaperConfig {
  bool enabled = true;
  WallpaperFillMode fillMode = WallpaperFillMode::Crop;
  std::vector<WallpaperTransition> transitions = {WallpaperTransition::Fade,     WallpaperTransition::Wipe,
                                                  WallpaperTransition::Disc,     WallpaperTransition::Stripes,
                                                  WallpaperTransition::Pixelate, WallpaperTransition::Honeycomb};
  float transitionDurationMs = 1500.0f;
  float edgeSmoothness = 0.5f;
  std::vector<WallpaperMonitorOverride> monitorOverrides;
};

struct OsdConfig {
  std::string position = "top_right";
};

struct Config {
  std::vector<BarConfig> bars;
  std::unordered_map<std::string, WidgetConfig> widgets;
  WallpaperConfig wallpaper;
  OsdConfig osd;
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

  void addReloadCallback(ReloadCallback callback);
  void checkReload();

  [[nodiscard]] static BarConfig resolveForOutput(const BarConfig& base, const WaylandOutput& output);

private:
  static void seedBuiltinWidgets(Config& config);
  void loadFromFile(const std::string& path);
  void setupWatch();

  Config m_config;
  std::string m_configPath;
  int m_inotifyFd = -1;
  int m_watchFd = -1;
  bool m_pendingReload = false;
  std::vector<ReloadCallback> m_reloadCallbacks;
};
