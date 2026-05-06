#pragma once

#include "ui/palette.h"
#include "ui/style.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <variant>
#include <vector>

struct WaylandOutput;

struct BarMonitorOverride {
  std::string match;
  std::optional<bool> enabled;
  std::optional<bool> autoHide;
  std::optional<bool> reserveSpace;
  std::optional<std::int32_t> thickness;
  std::optional<float> backgroundOpacity;
  std::optional<std::int32_t> radius;
  std::optional<std::int32_t> radiusTopLeft;
  std::optional<std::int32_t> radiusTopRight;
  std::optional<std::int32_t> radiusBottomLeft;
  std::optional<std::int32_t> radiusBottomRight;
  std::optional<std::int32_t> marginEnds;    // inset from each end of the bar along its main axis
  std::optional<std::int32_t> marginEdge;    // distance from the nearest screen edge (floats the bar when > 0)
  std::optional<std::int32_t> padding;       // main-axis padding from bar edges to start/end sections
  std::optional<std::int32_t> widgetSpacing; // gap between widgets within a section
  std::optional<bool> shadow;                // use the global shell shadow on this bar
  std::optional<bool> contactShadow;         // dark gradient between attached panel and bar
  std::optional<bool> attachPanels;          // allow panels to attach to this bar
  std::optional<float> scale;
  std::optional<std::vector<std::string>> startWidgets;
  std::optional<std::vector<std::string>> centerWidgets;
  std::optional<std::vector<std::string>> endWidgets;
  std::optional<bool> widgetCapsuleDefault;
  std::optional<ColorSpec> widgetCapsuleFill;
  bool widgetCapsuleBorderSpecified = false;
  std::optional<ColorSpec> widgetCapsuleBorder;
  std::optional<ColorSpec> widgetCapsuleForeground;
  std::optional<ColorSpec> widgetColor;
  std::optional<std::vector<std::string>> widgetCapsuleGroups;
  std::optional<double> widgetCapsulePadding;
  std::optional<double> widgetCapsuleOpacity;

  bool operator==(const BarMonitorOverride&) const = default;
};

struct BarConfig {
  std::string name = "default";
  std::string position = "top";
  bool enabled = true;
  bool autoHide = false;    // slide out when the pointer leaves; reveal on edge approach
  bool reserveSpace = true; // reserve compositor exclusive zone for this bar
  std::int32_t thickness = Style::barThicknessDefault;
  float backgroundOpacity = 1.0f;
  std::int32_t radius = static_cast<std::int32_t>(Style::radiusXl);
  std::int32_t radiusTopLeft = static_cast<std::int32_t>(Style::radiusXl);
  std::int32_t radiusTopRight = static_cast<std::int32_t>(Style::radiusXl);
  std::int32_t radiusBottomLeft = static_cast<std::int32_t>(Style::radiusXl);
  std::int32_t radiusBottomRight = static_cast<std::int32_t>(Style::radiusXl);
  std::int32_t marginEnds = 180;  // inset from each end of the bar along its main axis
  std::int32_t marginEdge = 10;   // distance from the nearest screen edge (floats the bar when > 0)
  std::int32_t padding = 14;      // main-axis padding from bar edges to start/end sections
  std::int32_t widgetSpacing = 6; // gap between widgets within a section
  bool shadow = true;             // use the global shell shadow
  bool contactShadow = false;     // dark gradient between attached panel and bar
  bool attachPanels = true;       // allow panels to attach to this bar
  float scale = 1.0f;             // content scale multiplier for glyphs and text
  std::vector<std::string> startWidgets = {"launcher", "wallpaper", "workspaces"};
  std::vector<std::string> centerWidgets = {"clock"};
  std::vector<std::string> endWidgets = {"media",   "tray",           "notifications", "clipboard",
                                         "network", "bluetooth",      "volume",        "brightness",
                                         "battery", "control-center", "session"};
  // When true, widgets on this bar use a capsule unless `[widget.*] capsule = false`.
  bool widgetCapsuleDefault = false;
  ColorSpec widgetCapsuleFill = colorSpecFromRole(ColorRole::SurfaceVariant);
  // When set, bar widgets with capsules use this for icon + primary label color unless overridden per widget.
  std::optional<ColorSpec> widgetCapsuleForeground;
  // Default icon + primary label color for all widgets on this bar (same as per-widget `color`); per-widget `color`
  // overrides.
  std::optional<ColorSpec> widgetColor;
  std::vector<std::string> widgetCapsuleGroups;
  // Inner padding between capsule edge and widget content (logical px), multiplied by widget content scale on the bar.
  float widgetCapsulePadding = Style::barCapsulePadding;
  // Capsule background opacity multiplier (0.0–1.0).
  float widgetCapsuleOpacity = 1.0f;
  // True when `capsule_border` appears under `[bar.*]` (empty value = no outline for widgets that inherit border).
  bool widgetCapsuleBorderSpecified = false;
  std::optional<ColorSpec> widgetCapsuleBorder;
  std::vector<BarMonitorOverride> monitorOverrides;

  bool operator==(const BarConfig&) const = default;
};

using WidgetSettingValue = std::variant<bool, std::int64_t, double, std::string, std::vector<std::string>>;
using ConfigOverrideValue = std::variant<bool, std::int64_t, double, std::string, std::vector<std::string>>;

// Optional rounded “capsule” behind a bar widget (see `[widget.*] capsule_*` in CONFIG.md).
// Corner shape (pill), border width, and edge softness are fixed in the shell code; padding is configurable.
struct WidgetBarCapsuleSpec {
  bool enabled = false;
  ColorSpec fill = colorSpecFromRole(ColorRole::SurfaceVariant);
  // Adjacent widgets in the same section with the same non-empty group and identical capsule styling share one shell.
  std::string group;
  // Set only when `capsule_border` is present and non-empty in config; otherwise no outline.
  std::optional<ColorSpec> border;
  // Icon + primary label color when the capsule is visible; unset = widget defaults.
  std::optional<ColorSpec> foreground;
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

// Color spec for `[widget.*] color` and other user color strings (same rules as `capsule_fill`).
[[nodiscard]] ColorSpec colorSpecFromConfigString(const std::string& raw);

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
  std::optional<ColorSpec> fillColor;
  std::optional<std::string> directory;
  std::optional<std::string> directoryLight;
  std::optional<std::string> directoryDark;
};

struct WallpaperAutomationConfig {
  enum class Order : std::uint8_t {
    Random = 0,
    Alphabetical = 1,
  };

  bool enabled = false;
  std::int32_t intervalMinutes = 0; // 0 = disabled
  Order order = Order::Random;
  bool recursive = true;
};

struct WallpaperConfig {
  bool enabled = true;
  WallpaperFillMode fillMode = WallpaperFillMode::Crop;
  std::optional<ColorSpec> fillColor;
  std::vector<WallpaperTransition> transitions = {WallpaperTransition::Fade, WallpaperTransition::Wipe,
                                                  WallpaperTransition::Disc, WallpaperTransition::Stripes,
                                                  WallpaperTransition::Zoom, WallpaperTransition::Honeycomb};
  float transitionDurationMs = 1500.0f;
  float edgeSmoothness = 0.3f;
  std::string directory;
  std::string directoryLight;
  std::string directoryDark;
  WallpaperAutomationConfig automation;
  std::vector<WallpaperMonitorOverride> monitorOverrides;
};

struct BackdropConfig {
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
  std::int32_t radius = 16;        // dock background corner radius
  std::int32_t marginEnds = 0;     // inset from each end of the dock along its main axis
  std::int32_t marginEdge = 8;     // distance from the nearest screen edge (floats the dock when > 0)
  bool shadow = true;              // use the global shell shadow
  bool showRunning = true;         // also show running apps not in pinned list
  bool autoHide = false;           // fade out when not hovered (overlay mode)
  bool reserveSpace = false;       // keep compositor exclusive zone even while auto-hidden
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
  bool enableDaemon = true;
  std::string position = "top_right";
  std::string layer = "top";       // top | overlay
  float backgroundOpacity = 0.97f; // toast card background alpha (0.0–1.0)
  std::vector<std::string> monitors;
};

template <typename T> struct EnumOption {
  T value;
  std::string_view key;
  std::string_view labelKey;
};

template <typename T, std::size_t N>
constexpr std::optional<T> enumFromKey(const EnumOption<T> (&options)[N], std::string_view key) {
  for (const auto& opt : options) {
    if (opt.key == key) {
      return opt.value;
    }
  }
  return std::nullopt;
}

template <typename T, std::size_t N> constexpr std::string_view enumToKey(const EnumOption<T> (&options)[N], T value) {
  for (const auto& opt : options) {
    if (opt.value == value) {
      return opt.key;
    }
  }
  return {};
}

enum class ClipboardAutoPasteMode : std::uint8_t {
  Off = 0,
  Auto = 1,
  CtrlV = 2,
  CtrlShiftV = 3,
  ShiftInsert = 4,
};

constexpr EnumOption<ClipboardAutoPasteMode> kClipboardAutoPasteModes[] = {
    {ClipboardAutoPasteMode::Off, "off", "common.states.off"},
    {ClipboardAutoPasteMode::Auto, "auto", "common.states.auto"},
    {ClipboardAutoPasteMode::CtrlV, "ctrl_v", "settings.options.clipboard.auto-paste.ctrl-v"},
    {ClipboardAutoPasteMode::CtrlShiftV, "ctrl_shift_v", "settings.options.clipboard.auto-paste.ctrl-shift-v"},
    {ClipboardAutoPasteMode::ShiftInsert, "shift_insert", "settings.options.clipboard.auto-paste.shift-insert"},
};

enum class PasswordMaskStyle : std::uint8_t {
  CircleFilled = 0,
  RandomIcons = 1,
};

constexpr EnumOption<PasswordMaskStyle> kPasswordMaskStyles[] = {
    {PasswordMaskStyle::CircleFilled, "default", "settings.options.shell.password-style.filled-circles"},
    {PasswordMaskStyle::RandomIcons, "random", "settings.options.shell.password-style.random-icons"},
};

constexpr EnumOption<WallpaperFillMode> kWallpaperFillModes[] = {
    {WallpaperFillMode::Center, "center", "settings.options.wallpaper.fill.center"},
    {WallpaperFillMode::Crop, "crop", "settings.options.wallpaper.fill.crop"},
    {WallpaperFillMode::Fit, "fit", "settings.options.wallpaper.fill.fit"},
    {WallpaperFillMode::Stretch, "stretch", "settings.options.wallpaper.fill.stretch"},
    {WallpaperFillMode::Repeat, "repeat", "settings.options.wallpaper.fill.repeat"},
};

constexpr EnumOption<WallpaperAutomationConfig::Order> kWallpaperAutomationOrders[] = {
    {WallpaperAutomationConfig::Order::Random, "random", "settings.options.wallpaper.order.random"},
    {WallpaperAutomationConfig::Order::Alphabetical, "alphabetical", "settings.options.wallpaper.order.alphabetical"},
};

constexpr EnumOption<WallpaperTransition> kWallpaperTransitions[] = {
    {WallpaperTransition::Disc, "disc", "settings.options.wallpaper.transition.disc"},
    {WallpaperTransition::Fade, "fade", "settings.options.wallpaper.transition.fade"},
    {WallpaperTransition::Honeycomb, "honeycomb", "settings.options.wallpaper.transition.honeycomb"},
    {WallpaperTransition::Stripes, "stripes", "settings.options.wallpaper.transition.stripes"},
    {WallpaperTransition::Wipe, "wipe", "settings.options.wallpaper.transition.wipe"},
    {WallpaperTransition::Zoom, "zoom", "settings.options.wallpaper.transition.zoom"},
};

struct ShellConfig {
  struct AnimationConfig {
    bool enabled = true;
    float speed = 1.0f;
  };

  struct ShadowConfig {
    std::int32_t blur = 12;
    std::int32_t offsetX = 0;
    std::int32_t offsetY = 6;
    float alpha = 0.55f;

    bool operator==(const ShadowConfig&) const = default;
  };

  struct PanelConfig {
    bool backgroundBlur = true; // request compositor blur behind panels via ext-background-effect-v1

    bool operator==(const PanelConfig&) const = default;
  };

  struct ScreenCornersConfig {
    bool enabled = false;
    std::int32_t size = 32;

    bool operator==(const ScreenCornersConfig&) const = default;
  };

  struct MprisConfig {
    std::vector<std::string> blacklist;

    bool operator==(const MprisConfig&) const = default;
  };

  float uiScale = 1.0f;
  std::string fontFamily = "sans-serif";
  std::string lang; // empty = auto-detect from $LC_ALL/$LC_MESSAGES/$LANG
  bool offlineMode = false;
  bool telemetryEnabled = false;
  bool polkitAgent = false;
  PasswordMaskStyle passwordMaskStyle = PasswordMaskStyle::CircleFilled;
  AnimationConfig animation;
  std::string avatarPath;
  bool settingsShowAdvanced = false;
  bool showLocation = true;
  ClipboardAutoPasteMode clipboardAutoPaste = ClipboardAutoPasteMode::Auto;
  ShadowConfig shadow;
  PanelConfig panel;
  ScreenCornersConfig screenCorners;
  MprisConfig mpris;
};

struct WeatherConfig {
  bool enabled = true;
  bool autoLocate = false;
  bool effects = true;
  std::string address;
  std::int32_t refreshMinutes = 30;
  std::string unit = "metric";
};

struct SystemConfig {
  struct MonitorConfig {
    bool enabled = true;
  };

  MonitorConfig monitor;
};

struct AudioConfig {
  bool enableOverdrive = false;
  bool enableSounds = false;
  float soundVolume = 0.5f;
  std::string volumeChangeSound;
  std::string notificationSound;
};

enum class BrightnessBackendPreference : std::uint8_t {
  Auto = 0,
  None = 1,
  Backlight = 2,
  Ddcutil = 3,
};

constexpr EnumOption<BrightnessBackendPreference> kBrightnessBackendPreferences[] = {
    {BrightnessBackendPreference::Auto, "auto", ""},
    {BrightnessBackendPreference::None, "none", ""},
    {BrightnessBackendPreference::Backlight, "backlight", ""},
    {BrightnessBackendPreference::Ddcutil, "ddcutil", ""},
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
  // wlsunset requires day > night with at least this much headroom, in Kelvin.
  static constexpr std::int32_t kTemperatureMin = 1000;
  static constexpr std::int32_t kTemperatureMax = 10000;
  static constexpr std::int32_t kTemperatureGap = 100;

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
  std::string resumeCommand;
};

struct IdleConfig {
  std::vector<IdleBehaviorConfig> behaviors;
};

enum class HookKind : std::uint8_t {
  Started = 0,
  WallpaperChanged,
  ColorsChanged,
  SessionLocked,
  SessionUnlocked,
  LoggingOut,
  Rebooting,
  ShuttingDown,
  WifiEnabled,
  WifiDisabled,
  BluetoothEnabled,
  BluetoothDisabled,
  BatteryStateChanged,
  BatteryUnderThreshold,
  Count
};

constexpr EnumOption<HookKind> kHookKinds[] = {
    {HookKind::Started, "started", ""},
    {HookKind::WallpaperChanged, "wallpaper_changed", ""},
    {HookKind::ColorsChanged, "colors_changed", ""},
    {HookKind::SessionLocked, "session_locked", ""},
    {HookKind::SessionUnlocked, "session_unlocked", ""},
    {HookKind::LoggingOut, "logging_out", ""},
    {HookKind::Rebooting, "rebooting", ""},
    {HookKind::ShuttingDown, "shutting_down", ""},
    {HookKind::WifiEnabled, "wifi_enabled", ""},
    {HookKind::WifiDisabled, "wifi_disabled", ""},
    {HookKind::BluetoothEnabled, "bluetooth_enabled", ""},
    {HookKind::BluetoothDisabled, "bluetooth_disabled", ""},
    {HookKind::BatteryStateChanged, "battery_state_changed", ""},
    {HookKind::BatteryUnderThreshold, "battery_under_threshold", ""},
};

static_assert(sizeof(kHookKinds) / sizeof(kHookKinds[0]) == static_cast<std::size_t>(HookKind::Count));

struct HooksConfig {
  std::array<std::vector<std::string>, static_cast<std::size_t>(HookKind::Count)> commands{};
  // When > 0, `battery_under_threshold` fires when charge crosses from above to at or below this value.
  // When 0, the under-threshold hook never runs.
  std::int32_t batteryLowPercentThreshold = 0;

  bool operator==(const HooksConfig&) const = default;
};

std::optional<HookKind> hookKindFromKey(std::string_view key);
std::string_view hookKindKey(HookKind kind);

enum class ThemeSource : std::uint8_t {
  Builtin = 0,
  Wallpaper = 1,
  Community = 2,
};

constexpr EnumOption<ThemeSource> kThemeSources[] = {
    {ThemeSource::Builtin, "builtin", "settings.options.theme.source.built-in"},
    {ThemeSource::Wallpaper, "wallpaper", "settings.options.theme.source.wallpaper"},
    {ThemeSource::Community, "community", "settings.options.theme.source.community"},
};

enum class ThemeMode : std::uint8_t {
  Dark = 0,
  Light = 1,
  Auto = 2,
};

constexpr EnumOption<ThemeMode> kThemeModes[] = {
    {ThemeMode::Dark, "dark", "settings.options.theme.mode.dark"},
    {ThemeMode::Light, "light", "settings.options.theme.mode.light"},
    {ThemeMode::Auto, "auto", "common.states.auto"},
};

struct ThemeConfig {
  struct TemplatesConfig {
    bool enableBuiltinTemplates = true;
    std::vector<std::string> builtinIds;
    bool enableCommunityTemplates = true;
    std::vector<std::string> communityIds;
    bool enableUserTemplates = false;
    std::string userConfig = "~/.config/noctalia/user-templates.toml";

    bool operator==(const TemplatesConfig&) const = default;
  };

  ThemeSource source = ThemeSource::Builtin;
  std::string builtinPalette = "Noctalia";
  std::string communityPalette = "Oxocarbon";
  std::string wallpaperScheme = "m3-content";
  ThemeMode mode = ThemeMode::Dark;
  TemplatesConfig templates;
};

struct ShortcutConfig {
  std::string type;
  std::optional<std::string> label;
  std::optional<std::string> icon;
  bool operator==(const ShortcutConfig&) const = default;
};

struct ControlCenterConfig {
  std::vector<ShortcutConfig> shortcuts;
  bool operator==(const ControlCenterConfig&) const = default;
};

struct Config {
  std::vector<BarConfig> bars;
  std::unordered_map<std::string, WidgetConfig> widgets;
  WallpaperConfig wallpaper;
  BackdropConfig backdrop;
  DockConfig dock;
  DesktopWidgetsConfig desktopWidgets;
  ShellConfig shell;
  OsdConfig osd;
  NotificationConfig notification;
  WeatherConfig weather;
  SystemConfig system;
  AudioConfig audio;
  BrightnessConfig brightness;
  KeybindsConfig keybinds;
  NightLightConfig nightlight;
  IdleConfig idle;
  HooksConfig hooks;
  ThemeConfig theme;
  ControlCenterConfig controlCenter;
};
