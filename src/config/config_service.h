#pragma once

#include "ui/palette.h"
#include "ui/style.h"

#include "core/toml.h"

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <unordered_map>
#include <variant>
#include <vector>

struct WaylandOutput;
class IpcService;
class NotificationManager;

struct BarMonitorOverride {
  std::string match;
  std::optional<bool> enabled;
  std::optional<std::int32_t> thickness;
  std::optional<float> backgroundOpacity;
  std::optional<std::int32_t> radius;
  std::optional<std::int32_t> radiusTopLeft;
  std::optional<std::int32_t> radiusTopRight;
  std::optional<std::int32_t> radiusBottomLeft;
  std::optional<std::int32_t> radiusBottomRight;
  std::optional<std::int32_t> marginH;       // horizontal compositor margin (left = right = marginH)
  std::optional<std::int32_t> marginV;       // vertical compositor margin (gap between bar and screen edge)
  std::optional<std::int32_t> padding;       // main-axis padding from bar edges to start/end sections
  std::optional<std::int32_t> widgetSpacing; // gap between widgets within a section
  std::optional<std::int32_t> shadowBlur;    // shadow blur radius in pixels (0 = no shadow)
  std::optional<std::int32_t> shadowOffsetX; // horizontal shadow offset in pixels
  std::optional<std::int32_t> shadowOffsetY; // vertical shadow offset in pixels (positive = down)
  std::optional<bool> backgroundBlur;        // request compositor blur via ext-background-effect-v1
  std::optional<float> scale;
  std::optional<std::vector<std::string>> startWidgets;
  std::optional<std::vector<std::string>> centerWidgets;
  std::optional<std::vector<std::string>> endWidgets;
  std::optional<bool> widgetCapsuleDefault;
  std::optional<std::string> widgetCapsuleFill;
  std::optional<std::string> widgetCapsuleBorder;
  std::optional<std::string> widgetCapsuleForeground;
  std::optional<std::string> widgetColor;
  std::optional<double> widgetCapsulePadding;
  std::optional<double> widgetCapsuleOpacity;

  bool operator==(const BarMonitorOverride&) const = default;
};

struct BarConfig {
  std::string name = "default";
  std::string position = "top";
  bool enabled = true;
  std::int32_t thickness = Style::barThicknessDefault;
  float backgroundOpacity = 1.0f;
  std::int32_t radius = Style::radiusXl;
  std::int32_t radiusTopLeft = Style::radiusXl;
  std::int32_t radiusTopRight = Style::radiusXl;
  std::int32_t radiusBottomLeft = Style::radiusXl;
  std::int32_t radiusBottomRight = Style::radiusXl;
  std::int32_t marginH = 180;     // horizontal compositor margin (left = right = marginH)
  std::int32_t marginV = 10;      // vertical compositor margin (gap between bar and screen edge)
  std::int32_t padding = 14;      // main-axis padding from bar edges to start/end sections
  std::int32_t widgetSpacing = 6; // gap between widgets within a section
  std::int32_t shadowBlur = 12;   // shadow blur radius in pixels (0 = no shadow)
  std::int32_t shadowOffsetX = 0; // horizontal shadow offset in pixels
  std::int32_t shadowOffsetY = 6; // vertical shadow offset in pixels (positive = down)
  bool backgroundBlur =
      true;           // request compositor blur behind the bar via ext-background-effect-v1 (inert where unsupported)
  float scale = 1.0f; // content scale multiplier for glyphs and text
  std::vector<std::string> startWidgets = {"launcher", "wallpaper", "workspaces"};
  std::vector<std::string> centerWidgets = {"clock"};
  std::vector<std::string> endWidgets = {"media",  "tray",       "notifications", "network", "bluetooth",
                                         "volume", "brightness", "battery",       "session"};
  // When true, widgets on this bar use a capsule unless `[widget.*] capsule = false`.
  bool widgetCapsuleDefault = false;
  ThemeColor widgetCapsuleFill = roleColor(ColorRole::SurfaceVariant);
  // When set, bar widgets with capsules use this for icon + primary label color unless overridden per widget.
  std::optional<ThemeColor> widgetCapsuleForeground;
  // Default icon + primary label color for all widgets on this bar (same as per-widget `color`); per-widget `color`
  // overrides.
  std::optional<ThemeColor> widgetColor;
  // Inner padding between capsule edge and widget content (logical px), multiplied by widget content scale on the bar.
  float widgetCapsulePadding = Style::barCapsulePadding;
  // Capsule background opacity multiplier (0.0–1.0).
  float widgetCapsuleOpacity = 1.0f;
  // True when `capsule_border` appears under `[bar.*]` (empty value = no outline for widgets that inherit border).
  bool widgetCapsuleBorderSpecified = false;
  std::optional<ThemeColor> widgetCapsuleBorder;
  std::vector<BarMonitorOverride> monitorOverrides;

  bool operator==(const BarConfig&) const = default;
};

using WidgetSettingValue = std::variant<bool, std::int64_t, double, std::string, std::vector<std::string>>;

// Optional rounded “capsule” behind a bar widget (see `[widget.*] capsule_*` in CONFIG.md).
// Corner shape (pill), border width, and edge softness are fixed in the shell code; padding is configurable.
struct WidgetBarCapsuleSpec {
  bool enabled = false;
  ThemeColor fill = roleColor(ColorRole::SurfaceVariant);
  // Set only when `capsule_border` is present and non-empty in config; otherwise no outline.
  std::optional<ThemeColor> border;
  // Icon + primary label color when the capsule is visible (theme role or `#` hex); unset = widget defaults.
  std::optional<ThemeColor> foreground;
  // Inner padding in logical pixels before content-scale (see `capsule_padding` / bar default).
  float padding = Style::barCapsulePadding;
  // Capsule background opacity multiplier (0.0–1.0).
  float opacity = 1.0f;

  bool operator==(const WidgetBarCapsuleSpec&) const = default;
};

struct WidgetConfig {
  std::string type; // widget type (e.g. "clock", "spacer"); defaults to the entry name
  std::unordered_map<std::string, WidgetSettingValue> settings;

  [[nodiscard]] std::string getString(const std::string& key, const std::string& fallback = {}) const;
  [[nodiscard]] std::vector<std::string> getStringList(const std::string& key,
                                                       const std::vector<std::string>& fallback = {}) const;
  [[nodiscard]] std::int64_t getInt(const std::string& key, std::int64_t fallback = 0) const;
  [[nodiscard]] double getDouble(const std::string& key, double fallback = 0.0) const;
  [[nodiscard]] bool getBool(const std::string& key, bool fallback = false) const;
  [[nodiscard]] bool hasSetting(const std::string& key) const;

  bool operator==(const WidgetConfig&) const = default;
};

// Merges `[bar.*]` capsule defaults with `[widget.*]` overrides (see CONFIG.md).
[[nodiscard]] WidgetBarCapsuleSpec resolveWidgetBarCapsuleSpec(const BarConfig& bar, const WidgetConfig* widget);

// Theme role or `#` hex for `[widget.*] color` and other user color strings (same rules as `capsule_fill`).
[[nodiscard]] ThemeColor themeColorFromConfigString(const std::string& raw);

// Shared output selector matching used by monitor-scoped config and IPC selectors.
// Matches connector name exactly, or a word-boundary token within output description.
[[nodiscard]] bool outputMatchesSelector(const std::string& match, const WaylandOutput& output);

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
  std::optional<std::string> directory;
  std::optional<std::string> directoryLight;
  std::optional<std::string> directoryDark;
};

struct WallpaperConfig {
  bool enabled = true;
  WallpaperFillMode fillMode = WallpaperFillMode::Crop;
  std::vector<WallpaperTransition> transitions = {WallpaperTransition::Fade, WallpaperTransition::Wipe,
                                                  WallpaperTransition::Disc, WallpaperTransition::Stripes,
                                                  WallpaperTransition::Zoom, WallpaperTransition::Honeycomb};
  float transitionDurationMs = 1500.0f;
  float edgeSmoothness = 0.3f;
  std::string directory;
  std::string directoryLight;
  std::string directoryDark;
  std::vector<WallpaperMonitorOverride> monitorOverrides;
};

struct OverviewConfig {
  bool enabled = false;
  float blurIntensity = 0.5f;
  float tintIntensity = 0.3f;
};

struct DockConfig {
  bool enabled = false;            // opt-in; dock is hidden by default
  std::string position = "bottom"; // top | bottom | left | right
  bool activeMonitorOnly = false;  // render only on preferred active output
  std::int32_t iconSize = 48;      // icon size in pixels (before ui_scale)
  std::int32_t padding = 8;        // inner padding around the icon row
  std::int32_t itemSpacing = 6;    // gap between items
  float backgroundOpacity = 0.88f;
  std::int32_t radius = 16; // dock background corner radius
  std::int32_t marginH = 0; // horizontal compositor margin from screen edges
  std::int32_t marginV = 8; // vertical gap between dock and screen edge
  std::int32_t shadowBlur = 12;
  std::int32_t shadowOffsetX = 0;
  std::int32_t shadowOffsetY = 4;
  bool backgroundBlur = true;
  bool showRunning = true;         // also show running apps not in pinned list
  bool autoHide = false;           // fade out when not hovered (overlay mode)
  float activeScale = 1.0f;        // focused app icon scale
  float inactiveScale = 0.85f;     // non-focused app icon scale
  float activeOpacity = 1.0f;      // focused app icon opacity
  float inactiveOpacity = 0.85f;   // non-focused app icon opacity
  bool showInstanceCount = true;   // show a badge with count when app has >1 window
  std::vector<std::string> pinned; // desktop entry IDs to always show

  bool operator==(const DockConfig&) const = default;
};

struct DesktopWidgetsConfig {
  bool enabled = true;

  bool operator==(const DesktopWidgetsConfig&) const = default;
};

struct OsdConfig {
  std::string position = "top_right";
};

struct NotificationConfig {
  float backgroundOpacity = 0.97f; // toast card background alpha (0.0–1.0)
  bool backgroundBlur = true;
};

enum class ClipboardAutoPasteMode : std::uint8_t {
  Off = 0,
  Auto = 1,
  CtrlV = 2,
  CtrlShiftV = 3,
  ShiftInsert = 4,
};

enum class PasswordMaskStyle : std::uint8_t {
  CircleFilled = 0,
  RandomIcons = 1,
};

struct ShellConfig {
  struct AnimationConfig {
    bool enabled = true;
    float speed = 1.0f;
  };

  float uiScale = 1.0f;
  std::string fontFamily = "sans-serif";
  std::string lang; // empty = auto-detect from $LC_ALL/$LC_MESSAGES/$LANG
  bool notificationsDbus = true;
  bool polkitAgent = false;
  PasswordMaskStyle passwordMaskStyle = PasswordMaskStyle::CircleFilled;
  AnimationConfig animation;
  std::string avatarPath;
  ClipboardAutoPasteMode clipboardAutoPaste = ClipboardAutoPasteMode::Auto;
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

enum class BrightnessBackendPreference : std::uint8_t {
  Auto = 0,
  None = 1,
  Backlight = 2,
  Ddcutil = 3,
};

struct BrightnessMonitorOverride {
  std::string match;
  std::optional<BrightnessBackendPreference> backend;

  bool operator==(const BrightnessMonitorOverride&) const = default;
};

struct BrightnessConfig {
  bool enableDdcutil = false;
  std::vector<std::string> ddcutilIgnoreMmids;
  std::vector<BrightnessMonitorOverride> monitorOverrides;

  bool operator==(const BrightnessConfig&) const = default;
};

enum class KeybindAction : std::uint8_t {
  Validate = 0,
  Cancel = 1,
  Left = 2,
  Right = 3,
  Up = 4,
  Down = 5,
};

struct KeyChord {
  std::uint32_t sym = 0;       // XKB keysym
  std::uint32_t modifiers = 0; // KeyMod bitmask

  bool operator==(const KeyChord&) const = default;
};

struct KeybindsConfig {
  std::vector<KeyChord> validate;
  std::vector<KeyChord> cancel;
  std::vector<KeyChord> left;
  std::vector<KeyChord> right;
  std::vector<KeyChord> up;
  std::vector<KeyChord> down;
};

struct NightLightConfig {
  bool enabled = false;
  bool force = false;
  bool useWeatherLocation = true; // use WeatherService coordinates when start/stop and explicit lat/long are not set
  std::string startTime;          // HH:MM sunset (night start), overrides location mode when paired with stop_time
  std::string stopTime;           // HH:MM sunrise (day start)
  std::optional<double> latitude;
  std::optional<double> longitude;
  std::int32_t dayTemperature = 6500;
  std::int32_t nightTemperature = 4000;
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

enum class ThemeSource : std::uint8_t {
  Builtin = 0,
  Wallpaper = 1,
  Community = 2,
};

enum class ThemeMode : std::uint8_t {
  Dark = 0,
  Light = 1,
  Auto = 2,
};

struct ThemeConfig {
  struct TemplatesConfig {
    bool enableBuiltins = true;
    std::vector<std::string> builtinIds;
    bool enableUserTemplates = false;
    std::string userConfig = "~/.config/noctalia/user-templates.toml";

    bool operator==(const TemplatesConfig&) const = default;
  };

  ThemeSource source = ThemeSource::Builtin;
  std::string builtinPalette = "Noctalia";
  std::string communityPalette = "Noctalia";
  std::string wallpaperScheme = "m3-content";
  ThemeMode mode = ThemeMode::Dark;
  TemplatesConfig templates;
};

struct Config {
  std::vector<BarConfig> bars;
  std::unordered_map<std::string, WidgetConfig> widgets;
  WallpaperConfig wallpaper;
  OverviewConfig overview;
  DockConfig dock;
  DesktopWidgetsConfig desktopWidgets;
  ShellConfig shell;
  OsdConfig osd;
  NotificationConfig notification;
  WeatherConfig weather;
  AudioConfig audio;
  BrightnessConfig brightness;
  KeybindsConfig keybinds;
  NightLightConfig nightlight;
  IdleConfig idle;
  ThemeConfig theme;
};

class ConfigService {
public:
  using ReloadCallback = std::function<void()>;
  using ChangeCallback = std::function<void()>;

  // RAII scope that coalesces wallpaper changes: any setWallpaperPath() calls
  // inside the scope skip the per-call callback, and a single callback is
  // fired on scope exit if anything actually changed.
  class WallpaperBatch {
  public:
    explicit WallpaperBatch(ConfigService& config);
    ~WallpaperBatch();
    WallpaperBatch(const WallpaperBatch&) = delete;
    WallpaperBatch& operator=(const WallpaperBatch&) = delete;

  private:
    ConfigService& m_config;
  };

  ConfigService();
  ~ConfigService();

  ConfigService(const ConfigService&) = delete;
  ConfigService& operator=(const ConfigService&) = delete;

  [[nodiscard]] const Config& config() const noexcept { return m_config; }
  [[nodiscard]] bool matchesKeybind(KeybindAction action, std::uint32_t sym, std::uint32_t modifiers) const;
  [[nodiscard]] int watchFd() const noexcept { return m_inotifyFd; }

  void addReloadCallback(ReloadCallback callback);
  void setNotificationManager(NotificationManager* manager);
  void checkReload();
  void forceReload();

  void registerIpc(IpcService& ipc);

  // Persisted wallpaper paths (written to overrides.toml, app-managed).
  [[nodiscard]] std::string getWallpaperPath(const std::string& connectorName) const;
  [[nodiscard]] std::string getDefaultWallpaperPath() const;
  void setWallpaperPath(const std::optional<std::string>& connectorName, const std::string& path);
  void setWallpaperChangeCallback(ChangeCallback callback);

  // Persist a theme-mode override to overrides.toml and trigger the reload pipeline.
  void setThemeMode(ThemeMode mode);
  // Persist dock enabled override to overrides.toml and trigger the reload pipeline.
  void setDockEnabled(bool enabled);

  [[nodiscard]] static BarConfig resolveForOutput(const BarConfig& base, const WaylandOutput& output);

private:
  static void seedBuiltinWidgets(Config& config);
  static void deepMerge(toml::table& base, const toml::table& overlay);
  void loadAll();
  void parseTable(const toml::table& tbl);
  void setupWatch();
  void fireReloadCallbacks();
  void loadOverridesFromFile();
  bool writeOverridesToFile();
  void extractWallpaperFromOverrides();

  Config m_config;

  // Hand-authored config directory: all *.toml merged alphabetically.
  std::string m_configDir;

  // App-writable overrides file (state dir): lives outside config dir so it
  // can still be written when the config dir is read-only (e.g. NixOS).
  std::string m_overridesPath;
  toml::table m_overridesTable;
  std::string m_defaultWallpaperPath;
  std::unordered_map<std::string, std::string> m_monitorWallpaperPaths;

  std::string m_pendingError; // parse error from initial load, sent as notification once manager is wired up
  uint32_t m_configErrorNotificationId = 0; // ID of the active config-error notification, 0 if none
  NotificationManager* m_notificationManager = nullptr;

  // Single inotify fd, two watch descriptors (config dir + state dir).
  int m_inotifyFd = -1;
  int m_configWatchWd = -1;
  int m_overridesWatchWd = -1;
  // Extra watches on symlink-target directories: wd → list of filenames to match.
  std::unordered_map<int, std::vector<std::string>> m_symlinkDirWds;

  bool m_ownOverridesWritePending = false;
  int m_wallpaperBatchDepth = 0;
  bool m_wallpaperBatchDirty = false;

  ChangeCallback m_wallpaperChangeCallback;
  std::vector<ReloadCallback> m_reloadCallbacks;
};
