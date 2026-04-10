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
class NotificationManager;

struct BarMonitorOverride {
  std::string match;
  std::optional<bool> enabled;
  std::optional<std::int32_t> height;
  std::optional<float> backgroundOpacity;
  std::optional<std::int32_t> radius;
  std::optional<std::int32_t> radiusOuter;
  std::optional<std::int32_t> radiusInner;
  std::optional<std::int32_t> marginH;       // horizontal compositor margin (left = right = marginH)
  std::optional<std::int32_t> marginV;       // vertical compositor margin (gap between bar and screen edge)
  std::optional<std::int32_t> paddingH;      // horizontal padding from bar edges to start/end sections
  std::optional<std::int32_t> widgetSpacing; // gap between widgets within a section
  std::optional<std::int32_t> shadowBlur;    // shadow blur radius in pixels (0 = no shadow)
  std::optional<std::int32_t> shadowOffsetX; // horizontal shadow offset in pixels
  std::optional<std::int32_t> shadowOffsetY; // vertical shadow offset in pixels (positive = down)
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
  float backgroundOpacity = 1.0f;
  std::int32_t radius = Style::radiusXl;
  std::int32_t radiusOuter = Style::radiusXl;
  std::int32_t radiusInner = Style::radiusXl;
  std::int32_t marginH = 180;     // horizontal compositor margin (left = right = marginH)
  std::int32_t marginV = 10;      // vertical compositor margin (gap between bar and screen edge)
  std::int32_t paddingH = 14;     // horizontal padding from bar edges to start/end sections
  std::int32_t widgetSpacing = 6; // gap between widgets within a section
  std::int32_t shadowBlur = 12;   // shadow blur radius in pixels (0 = no shadow)
  std::int32_t shadowOffsetX = 0; // horizontal shadow offset in pixels
  std::int32_t shadowOffsetY = 6; // vertical shadow offset in pixels (positive = down)
  float scale = 1.0f;             // content scale multiplier for glyphs and text
  std::vector<std::string> startWidgets = {"cpu", "temp", "ram", "active_window"};
  std::vector<std::string> centerWidgets = {"workspaces"};
  std::vector<std::string> endWidgets = {"media",   "tray",    "notifications", "volume", "power_profiles",
                                         "battery", "session", "spacer",        "date",   "clock"};
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
  Zoom = 4,
  Honeycomb = 5,
};

struct WallpaperMonitorOverride {
  std::string match;
  std::optional<bool> enabled;
};

struct WallpaperConfig {
  bool enabled = true;
  WallpaperFillMode fillMode = WallpaperFillMode::Crop;
  std::vector<WallpaperTransition> transitions = {WallpaperTransition::Fade, WallpaperTransition::Wipe,
                                                  WallpaperTransition::Disc, WallpaperTransition::Stripes,
                                                  WallpaperTransition::Zoom, WallpaperTransition::Honeycomb};
  float transitionDurationMs = 1500.0f;
  float edgeSmoothness = 0.3f;
  std::vector<WallpaperMonitorOverride> monitorOverrides;
};

struct OverviewConfig {
  bool enabled = false;
  float blurIntensity = 0.5f;
  float tintIntensity = 0.3f;
};

struct OsdConfig {
  std::string position = "top_right";
};

struct ShellConfig {
  float uiScale = 1.0f;
  std::string lang; // empty = auto-detect from $LC_ALL/$LC_MESSAGES/$LANG
  bool notificationsDbus = true;
  std::string avatarPath;
};

struct WeatherConfig {
  bool enabled = true;
  bool autoLocate = false;
  std::string address;
  std::int32_t refreshMinutes = 30;
  std::string unit = "celsius";
};

struct AudioConfig {
  bool enableOverdrive = false;
};

struct IdleBehaviorConfig {
  std::string name;
  bool enabled = true;
  std::int32_t timeoutSeconds = 0;
  std::string command;
};

struct IdleConfig {
  std::vector<IdleBehaviorConfig> behaviors;
};

struct Config {
  std::vector<BarConfig> bars;
  std::unordered_map<std::string, WidgetConfig> widgets;
  WallpaperConfig wallpaper;
  OverviewConfig overview;
  ShellConfig shell;
  OsdConfig osd;
  WeatherConfig weather;
  AudioConfig audio;
  IdleConfig idle;
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
  void setNotificationManager(NotificationManager* manager);
  void checkReload();
  void forceReload();

  [[nodiscard]] static BarConfig resolveForOutput(const BarConfig& base, const WaylandOutput& output);

private:
  static void seedBuiltinWidgets(Config& config);
  void loadFromFile(const std::string& path);
  void setupWatch();

  Config m_config;
  std::string m_configPath;
  std::string m_pendingError; // parse error from initial load, sent as notification once manager is wired up
  uint32_t m_configErrorNotificationId = 0; // ID of the active config-error notification, 0 if none
  NotificationManager* m_notificationManager = nullptr;
  int m_inotifyFd = -1;
  int m_watchFd = -1;
  bool m_pendingReload = false;
  std::vector<ReloadCallback> m_reloadCallbacks;
};
