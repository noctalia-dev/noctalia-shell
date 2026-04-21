#include "config/config_service.h"

#include "core/log.h"
#include "ipc/ipc_service.h"
#include "notification/notification_manager.h"
#include "render/core/color.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <optional>
#include <stdexcept>
#include <string_view>
#include <sys/inotify.h>
#include <unistd.h>
#include <vector>
#include <xkbcommon/xkbcommon.h>

namespace {

  std::string configDir() {
    const char* xdg = std::getenv("XDG_CONFIG_HOME");
    if (xdg != nullptr && xdg[0] != '\0') {
      return std::string(xdg) + "/noctalia";
    }
    const char* home = std::getenv("HOME");
    if (home != nullptr && home[0] != '\0') {
      return std::string(home) + "/.config/noctalia";
    }
    return {};
  }

  std::string stateDir() {
    const char* xdg = std::getenv("XDG_STATE_HOME");
    if (xdg != nullptr && xdg[0] != '\0') {
      return std::string(xdg) + "/noctalia";
    }
    const char* home = std::getenv("HOME");
    if (home != nullptr && home[0] != '\0') {
      return std::string(home) + "/.local/state/noctalia";
    }
    return {};
  }

  const char* themeModeString(ThemeMode mode) {
    switch (mode) {
    case ThemeMode::Dark:
      return "dark";
    case ThemeMode::Light:
      return "light";
    case ThemeMode::Auto:
      return "auto";
    }
    return "dark";
  }

  toml::table* ensureTable(toml::table& parent, std::string_view key) {
    if (auto* existing = parent.get_as<toml::table>(key)) {
      return existing;
    }
    auto [it, _] = parent.insert_or_assign(key, toml::table{});
    return it->second.as_table();
  }

  std::vector<std::string> readStringArray(const toml::node& node) {
    std::vector<std::string> result;
    if (auto* arr = node.as_array()) {
      for (const auto& item : *arr) {
        if (auto* str = item.as_string()) {
          result.push_back(str->get());
        }
      }
    }
    return result;
  }

  void setHookCommandsFromNode(const toml::node& node, std::vector<std::string>& out) {
    out.clear();
    if (auto* s = node.as_string()) {
      const auto& val = s->get();
      if (!val.empty()) {
        out.push_back(val);
      }
      return;
    }
    for (const auto& line : readStringArray(node)) {
      if (!line.empty()) {
        out.push_back(line);
      }
    }
  }

  constexpr std::pair<std::string_view, HookKind> kHookKindByName[] = {
      {"started", HookKind::Started},
      {"wallpaper_changed", HookKind::WallpaperChanged},
      {"colors_changed", HookKind::ColorsChanged},
      {"session_locked", HookKind::SessionLocked},
      {"session_unlocked", HookKind::SessionUnlocked},
      {"logging_out", HookKind::LoggingOut},
      {"rebooting", HookKind::Rebooting},
      {"shutting_down", HookKind::ShuttingDown},
      {"wifi_enabled", HookKind::WifiEnabled},
      {"wifi_disabled", HookKind::WifiDisabled},
      {"bluetooth_enabled", HookKind::BluetoothEnabled},
      {"bluetooth_disabled", HookKind::BluetoothDisabled},
      {"battery_state_changed", HookKind::BatteryStateChanged},
      {"battery_under_threshold", HookKind::BatteryUnderThreshold},
  };

  std::optional<HookKind> hookKindFromKey(std::string_view key) {
    for (const auto& [name, kind] : kHookKindByName) {
      if (key == name) {
        return kind;
      }
    }
    return std::nullopt;
  }

  std::string trim(std::string_view input) {
    std::size_t start = 0;
    while (start < input.size() && std::isspace(static_cast<unsigned char>(input[start])) != 0) {
      ++start;
    }
    std::size_t end = input.size();
    while (end > start && std::isspace(static_cast<unsigned char>(input[end - 1])) != 0) {
      --end;
    }
    return std::string(input.substr(start, end - start));
  }

  std::string toLower(std::string_view input) {
    std::string out(input);
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return out;
  }

  std::optional<BrightnessBackendPreference> parseBrightnessBackendPreference(std::string_view raw) {
    const std::string value = toLower(trim(raw));
    if (value.empty() || value == "auto") {
      return BrightnessBackendPreference::Auto;
    }
    if (value == "none" || value == "off" || value == "disabled") {
      return BrightnessBackendPreference::None;
    }
    if (value == "backlight" || value == "sysfs") {
      return BrightnessBackendPreference::Backlight;
    }
    if (value == "ddcutil" || value == "ddc" || value == "ddcci" || value == "ddc/ci") {
      return BrightnessBackendPreference::Ddcutil;
    }
    return std::nullopt;
  }

  std::optional<KeyChord> parseKeyChord(std::string_view rawSpec) {
    const std::string spec = trim(rawSpec);
    if (spec.empty()) {
      return std::nullopt;
    }

    std::vector<std::string> tokens;
    std::size_t start = 0;
    while (start <= spec.size()) {
      const std::size_t plus = spec.find('+', start);
      const std::size_t len = (plus == std::string::npos) ? (spec.size() - start) : (plus - start);
      const std::string token = trim(std::string_view(spec).substr(start, len));
      if (token.empty()) {
        return std::nullopt;
      }
      tokens.push_back(token);
      if (plus == std::string::npos) {
        break;
      }
      start = plus + 1;
    }

    if (tokens.empty()) {
      return std::nullopt;
    }

    std::uint32_t modifiers = 0;
    for (std::size_t i = 0; i + 1 < tokens.size(); ++i) {
      const std::string mod = toLower(tokens[i]);
      if (mod == "ctrl" || mod == "control" || mod == "ctl") {
        modifiers |= KeyMod::Ctrl;
      } else if (mod == "shift") {
        modifiers |= KeyMod::Shift;
      } else if (mod == "alt" || mod == "option") {
        modifiers |= KeyMod::Alt;
      } else if (mod == "super" || mod == "meta" || mod == "logo" || mod == "win" || mod == "mod4") {
        throw std::runtime_error("modifier \"super/windows\" is not allowed");
      } else {
        return std::nullopt;
      }
    }

    std::string keyName = toLower(tokens.back());
    if (keyName == "esc") {
      keyName = "Escape";
    } else if (keyName == "enter") {
      keyName = "Return";
    } else if (keyName == "kp_enter") {
      keyName = "KP_Enter";
    } else if (keyName == "space" || keyName == "spacebar") {
      keyName = "space";
    } else if (keyName == "left") {
      keyName = "Left";
    } else if (keyName == "right") {
      keyName = "Right";
    } else if (keyName == "up") {
      keyName = "Up";
    } else if (keyName == "down") {
      keyName = "Down";
    }

    xkb_keysym_t sym = xkb_keysym_from_name(keyName.c_str(), XKB_KEYSYM_CASE_INSENSITIVE);
    if (sym == XKB_KEY_NoSymbol) {
      return std::nullopt;
    }

    return KeyChord{.sym = static_cast<std::uint32_t>(sym), .modifiers = modifiers};
  }

  const std::vector<KeyChord>& keybindSet(const KeybindsConfig& keybinds, KeybindAction action) {
    switch (action) {
    case KeybindAction::Validate:
      return keybinds.validate;
    case KeybindAction::Cancel:
      return keybinds.cancel;
    case KeybindAction::Left:
      return keybinds.left;
    case KeybindAction::Right:
      return keybinds.right;
    case KeybindAction::Up:
      return keybinds.up;
    case KeybindAction::Down:
      return keybinds.down;
    }
    return keybinds.validate;
  }

  std::vector<KeyChord> defaultKeybindSet(KeybindAction action) {
    switch (action) {
    case KeybindAction::Validate:
      return {{.sym = XKB_KEY_Return, .modifiers = 0}, {.sym = XKB_KEY_KP_Enter, .modifiers = 0}};
    case KeybindAction::Cancel:
      return {{.sym = XKB_KEY_Escape, .modifiers = 0}};
    case KeybindAction::Left:
      return {{.sym = XKB_KEY_Left, .modifiers = 0}};
    case KeybindAction::Right:
      return {{.sym = XKB_KEY_Right, .modifiers = 0}};
    case KeybindAction::Up:
      return {{.sym = XKB_KEY_Up, .modifiers = 0}};
    case KeybindAction::Down:
      return {{.sym = XKB_KEY_Down, .modifiers = 0}};
    }
    return {};
  }

  constexpr Logger kLog("config");

} // namespace

bool outputMatchesSelector(const std::string& match, const WaylandOutput& output) {
  // Exact connector name match.
  if (!output.connectorName.empty() && match == output.connectorName) {
    return true;
  }
  // Word-boundary substring match on description.
  // A bare substring search would let "DP-1" match "eDP-1" inside descriptions
  // like "BOE 0x0BCA eDP-1", so require the token to be surrounded by whitespace
  // or string boundaries.
  if (!output.description.empty()) {
    std::size_t pos = 0;
    while ((pos = output.description.find(match, pos)) != std::string::npos) {
      const bool startOk = (pos == 0 || std::isspace(static_cast<unsigned char>(output.description[pos - 1])) != 0);
      const bool endOk = (pos + match.size() == output.description.size() ||
                          std::isspace(static_cast<unsigned char>(output.description[pos + match.size()])) != 0);
      if (startOk && endOk) {
        return true;
      }
      ++pos;
    }
  }
  return false;
}

// ── Lifecycle ────────────────────────────────────────────────────────────────

ConfigService::WallpaperBatch::WallpaperBatch(ConfigService& config) : m_config(config) {
  ++m_config.m_wallpaperBatchDepth;
}

ConfigService::WallpaperBatch::~WallpaperBatch() {
  --m_config.m_wallpaperBatchDepth;
  if (m_config.m_wallpaperBatchDepth == 0 && m_config.m_wallpaperBatchDirty) {
    m_config.m_wallpaperBatchDirty = false;
    if (m_config.m_wallpaperChangeCallback) {
      m_config.m_wallpaperChangeCallback();
    }
  }
}

ConfigService::ConfigService() {
  m_configDir = configDir();

  // Resolve overrides.toml path; create the state dir eagerly so writes don't
  // race with directory creation later.
  if (auto dir = stateDir(); !dir.empty()) {
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    m_overridesPath = dir + "/overrides.toml";
  }

  loadOverridesFromFile();
  loadAll();
  setupWatch();
}

ConfigService::~ConfigService() {
  if (m_inotifyFd >= 0) {
    if (m_configWatchWd >= 0) {
      inotify_rm_watch(m_inotifyFd, m_configWatchWd);
    }
    if (m_overridesWatchWd >= 0) {
      inotify_rm_watch(m_inotifyFd, m_overridesWatchWd);
    }
    for (const auto& [wd, _] : m_symlinkDirWds) {
      if (wd != m_configWatchWd && wd != m_overridesWatchWd) {
        inotify_rm_watch(m_inotifyFd, wd);
      }
    }
    ::close(m_inotifyFd);
  }
}

// ── Public interface ─────────────────────────────────────────────────────────

void ConfigService::addReloadCallback(ReloadCallback callback) { m_reloadCallbacks.push_back(std::move(callback)); }

void ConfigService::setNotificationManager(NotificationManager* manager) {
  m_notificationManager = manager;
  if (m_notificationManager != nullptr && !m_pendingError.empty()) {
    m_configErrorNotificationId =
        m_notificationManager->addInternal("Noctalia", "Config parse error", m_pendingError, Urgency::Critical, 0);
    m_pendingError.clear();
  }
}

void ConfigService::forceReload() {
  loadAll();
  fireReloadCallbacks();
}

void ConfigService::fireReloadCallbacks() {
  for (const auto& cb : m_reloadCallbacks) {
    cb();
  }
}

void ConfigService::checkReload() {
  if (m_inotifyFd < 0) {
    return;
  }

  // Drain inotify events and bucket them per watch descriptor.
  alignas(inotify_event) char buf[4096];
  bool configChanged = false;
  bool overridesChanged = false;

  while (true) {
    const auto n = ::read(m_inotifyFd, buf, sizeof(buf));
    if (n <= 0) {
      break;
    }

    std::size_t offset = 0;
    while (offset < static_cast<std::size_t>(n)) {
      auto* event = reinterpret_cast<inotify_event*>(buf + offset);
      if (event->len > 0) {
        const std::string_view name{event->name};
        if (event->wd == m_configWatchWd) {
          if (name.size() >= 5 && name.substr(name.size() - 5) == ".toml") {
            configChanged = true;
          }
        } else if (event->wd == m_overridesWatchWd) {
          const auto overridesFilename = std::filesystem::path(m_overridesPath).filename().string();
          if (name == overridesFilename) {
            overridesChanged = true;
          }
        } else {
          // Check whether this event comes from a symlink-target directory.
          const auto symIt = m_symlinkDirWds.find(event->wd);
          if (symIt != m_symlinkDirWds.end()) {
            for (const auto& watched : symIt->second) {
              if (name == watched) {
                configChanged = true;
                break;
              }
            }
          }
        }
      }
      offset += sizeof(inotify_event) + event->len;
    }
  }

  // Skip the echo of our own write.
  if (overridesChanged && m_ownOverridesWritePending) {
    m_ownOverridesWritePending = false;
    overridesChanged = false;
  }

  if (overridesChanged) {
    kLog.info("reloading {}", m_overridesPath);

    const auto oldDefault = m_defaultWallpaperPath;
    const auto oldMonitors = m_monitorWallpaperPaths;

    loadOverridesFromFile();

    const bool wallpaperChanged = (oldDefault != m_defaultWallpaperPath || oldMonitors != m_monitorWallpaperPaths);
    if (wallpaperChanged && m_wallpaperChangeCallback) {
      m_wallpaperChangeCallback();
    }
    configChanged = true; // overrides affect Config — rebuild it
  }

  if (!configChanged) {
    return;
  }

  kLog.info("config changed, reloading");
  loadAll();
  fireReloadCallbacks();
}

void ConfigService::setThemeMode(ThemeMode mode) {
  if (m_overridesPath.empty()) {
    return;
  }

  auto* themeTbl = ensureTable(m_overridesTable, "theme");
  themeTbl->insert_or_assign("mode", std::string(themeModeString(mode)));

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;

  // Rebuild Config and fan out reload callbacks so ThemeService transitions.
  loadAll();
  fireReloadCallbacks();
}

void ConfigService::setDockEnabled(bool enabled) {
  if (m_overridesPath.empty()) {
    return;
  }

  auto* dockTbl = ensureTable(m_overridesTable, "dock");
  const auto existing = (*dockTbl)["enabled"].value<bool>();
  if (existing.has_value() && *existing == enabled && m_config.dock.enabled == enabled) {
    return;
  }

  dockTbl->insert_or_assign("enabled", enabled);

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;

  loadAll();
  fireReloadCallbacks();
}

std::string ConfigService::getWallpaperPath(const std::string& connectorName) const {
  auto it = m_monitorWallpaperPaths.find(connectorName);
  if (it != m_monitorWallpaperPaths.end()) {
    return it->second;
  }
  return m_defaultWallpaperPath;
}

std::string ConfigService::getDefaultWallpaperPath() const { return m_defaultWallpaperPath; }

void ConfigService::setWallpaperChangeCallback(ChangeCallback callback) {
  m_wallpaperChangeCallback = std::move(callback);
}

void ConfigService::setWallpaperPath(const std::optional<std::string>& connectorName, const std::string& path) {
  if (m_overridesPath.empty()) {
    return;
  }

  bool changed = false;
  if (connectorName.has_value()) {
    auto it = m_monitorWallpaperPaths.find(*connectorName);
    if (it == m_monitorWallpaperPaths.end() || it->second != path) {
      m_monitorWallpaperPaths[*connectorName] = path;
      changed = true;
    }
  } else {
    if (m_defaultWallpaperPath != path) {
      m_defaultWallpaperPath = path;
      changed = true;
    }
  }

  if (!changed) {
    return;
  }

  // Mirror the change into the overrides table so writeOverridesToFile() serializes it.
  auto* wallpaperTbl = ensureTable(m_overridesTable, "wallpaper");
  if (connectorName.has_value()) {
    auto* monitorsTbl = ensureTable(*wallpaperTbl, "monitors");
    auto* monTbl = ensureTable(*monitorsTbl, *connectorName);
    monTbl->insert_or_assign("path", path);
  } else {
    auto* defaultTbl = ensureTable(*wallpaperTbl, "default");
    defaultTbl->insert_or_assign("path", path);
  }

  if (!writeOverridesToFile()) {
    kLog.warn("failed to write {}", m_overridesPath);
    return;
  }

  m_ownOverridesWritePending = true;
  if (m_wallpaperBatchDepth > 0) {
    m_wallpaperBatchDirty = true;
    return;
  }
  if (m_wallpaperChangeCallback) {
    m_wallpaperChangeCallback();
  }
}

namespace {

  constexpr Logger kCapsuleLog("config");

  void trimAsciiInPlace(std::string& s) {
    while (!s.empty() && std::isspace(static_cast<unsigned char>(s.front())) != 0) {
      s.erase(s.begin());
    }
    while (!s.empty() && std::isspace(static_cast<unsigned char>(s.back())) != 0) {
      s.pop_back();
    }
  }

  std::optional<ColorRole> colorRoleFromToken(std::string token) {
    trimAsciiInPlace(token);
    for (auto& c : token) {
      if (c == '-') {
        c = '_';
      } else {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      }
    }
    if (token == "primary") {
      return ColorRole::Primary;
    }
    if (token == "on_primary") {
      return ColorRole::OnPrimary;
    }
    if (token == "secondary") {
      return ColorRole::Secondary;
    }
    if (token == "on_secondary") {
      return ColorRole::OnSecondary;
    }
    if (token == "tertiary") {
      return ColorRole::Tertiary;
    }
    if (token == "on_tertiary") {
      return ColorRole::OnTertiary;
    }
    if (token == "error") {
      return ColorRole::Error;
    }
    if (token == "on_error") {
      return ColorRole::OnError;
    }
    if (token == "surface") {
      return ColorRole::Surface;
    }
    if (token == "on_surface") {
      return ColorRole::OnSurface;
    }
    if (token == "surface_variant") {
      return ColorRole::SurfaceVariant;
    }
    if (token == "surface_secondary") {
      return ColorRole::Secondary;
    }
    if (token == "on_surface_variant") {
      return ColorRole::OnSurfaceVariant;
    }
    if (token == "outline") {
      return ColorRole::Outline;
    }
    if (token == "shadow") {
      return ColorRole::Shadow;
    }
    if (token == "hover") {
      return ColorRole::Hover;
    }
    if (token == "on_hover") {
      return ColorRole::OnHover;
    }
    return std::nullopt;
  }

  ThemeColor themeColorFromCapsuleString(const std::string& raw) {
    std::string trimmed = raw;
    trimAsciiInPlace(trimmed);
    if (!trimmed.empty() && trimmed.front() == '#') {
      try {
        const Color c = hex(trimmed);
        return fixedColor(withAlpha(c, 1.0f));
      } catch (const std::invalid_argument&) {
        kCapsuleLog.warn("invalid capsule color \"{}\", using surface_variant", raw);
        return roleColor(ColorRole::SurfaceVariant);
      }
    }
    if (auto role = colorRoleFromToken(trimmed)) {
      return roleColor(*role);
    }
    kCapsuleLog.warn("unknown capsule color role \"{}\", using surface_variant", raw);
    return roleColor(ColorRole::SurfaceVariant);
  }

  std::optional<ThemeColor> optionalCapsuleBorder(const std::string& raw) {
    std::string t = raw;
    trimAsciiInPlace(t);
    if (t.empty()) {
      return std::nullopt;
    }
    return themeColorFromCapsuleString(t);
  }

} // namespace

ThemeColor themeColorFromConfigString(const std::string& raw) { return themeColorFromCapsuleString(raw); }

BarConfig ConfigService::resolveForOutput(const BarConfig& base, const WaylandOutput& output) {
  BarConfig resolved = base;

  for (const auto& ovr : base.monitorOverrides) {
    if (!outputMatchesSelector(ovr.match, output)) {
      continue;
    }

    kLog.debug("monitor override \"{}\" matched output {} ({})", ovr.match, output.connectorName, output.description);

    if (ovr.enabled)
      resolved.enabled = *ovr.enabled;
    if (ovr.autoHide)
      resolved.autoHide = *ovr.autoHide;
    if (ovr.reserveSpace)
      resolved.reserveSpace = *ovr.reserveSpace;
    if (ovr.thickness)
      resolved.thickness = *ovr.thickness;
    if (ovr.backgroundOpacity)
      resolved.backgroundOpacity = *ovr.backgroundOpacity;
    if (ovr.radius) {
      resolved.radius = *ovr.radius;
      resolved.radiusTopLeft = *ovr.radius;
      resolved.radiusTopRight = *ovr.radius;
      resolved.radiusBottomLeft = *ovr.radius;
      resolved.radiusBottomRight = *ovr.radius;
    }
    if (ovr.radiusTopLeft)
      resolved.radiusTopLeft = *ovr.radiusTopLeft;
    if (ovr.radiusTopRight)
      resolved.radiusTopRight = *ovr.radiusTopRight;
    if (ovr.radiusBottomLeft)
      resolved.radiusBottomLeft = *ovr.radiusBottomLeft;
    if (ovr.radiusBottomRight)
      resolved.radiusBottomRight = *ovr.radiusBottomRight;
    if (ovr.marginH)
      resolved.marginH = *ovr.marginH;
    if (ovr.marginV)
      resolved.marginV = *ovr.marginV;
    if (ovr.padding)
      resolved.padding = *ovr.padding;
    if (ovr.widgetSpacing)
      resolved.widgetSpacing = *ovr.widgetSpacing;
    if (ovr.shadowBlur)
      resolved.shadowBlur = *ovr.shadowBlur;
    if (ovr.shadowOffsetX)
      resolved.shadowOffsetX = *ovr.shadowOffsetX;
    if (ovr.shadowOffsetY)
      resolved.shadowOffsetY = *ovr.shadowOffsetY;
    if (ovr.backgroundBlur)
      resolved.backgroundBlur = *ovr.backgroundBlur;
    if (ovr.startWidgets)
      resolved.startWidgets = *ovr.startWidgets;
    if (ovr.centerWidgets)
      resolved.centerWidgets = *ovr.centerWidgets;
    if (ovr.endWidgets)
      resolved.endWidgets = *ovr.endWidgets;
    if (ovr.scale)
      resolved.scale = *ovr.scale;
    if (ovr.widgetCapsuleDefault)
      resolved.widgetCapsuleDefault = *ovr.widgetCapsuleDefault;
    if (ovr.widgetCapsuleFill)
      resolved.widgetCapsuleFill = themeColorFromCapsuleString(*ovr.widgetCapsuleFill);
    if (ovr.widgetCapsuleBorder) {
      resolved.widgetCapsuleBorderSpecified = true;
      resolved.widgetCapsuleBorder = optionalCapsuleBorder(*ovr.widgetCapsuleBorder);
    }
    if (ovr.widgetCapsuleForeground) {
      resolved.widgetCapsuleForeground = themeColorFromCapsuleString(*ovr.widgetCapsuleForeground);
    }
    if (ovr.widgetColor) {
      resolved.widgetColor = themeColorFromCapsuleString(*ovr.widgetColor);
    }
    if (ovr.widgetCapsulePadding) {
      resolved.widgetCapsulePadding = std::clamp(static_cast<float>(*ovr.widgetCapsulePadding), 0.0f, 48.0f);
    }
    if (ovr.widgetCapsuleOpacity) {
      resolved.widgetCapsuleOpacity = std::clamp(static_cast<float>(*ovr.widgetCapsuleOpacity), 0.0f, 1.0f);
    }
    break; // first match wins
  }

  return resolved;
}

// ── Private helpers ──────────────────────────────────────────────────────────

void ConfigService::setupWatch() {
  if (m_configDir.empty()) {
    return;
  }

  std::error_code ec;
  std::filesystem::create_directories(m_configDir, ec);

  m_inotifyFd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
  if (m_inotifyFd < 0) {
    kLog.warn("inotify_init1 failed, hot reload disabled");
    return;
  }

  m_configWatchWd =
      inotify_add_watch(m_inotifyFd, m_configDir.c_str(), IN_MODIFY | IN_CLOSE_WRITE | IN_CREATE | IN_MOVED_TO);
  if (m_configWatchWd < 0) {
    kLog.warn("inotify_add_watch failed, hot reload disabled");
    ::close(m_inotifyFd);
    m_inotifyFd = -1;
    return;
  }

  kLog.debug("watching {} for changes", m_configDir);

  // For any *.toml entries that are symlinks, also watch the real target's parent
  // directory so that edits to the target file (e.g. via dotfile management) trigger
  // a reload even though the modification event fires in a different directory.
  {
    std::error_code scanEc;
    for (const auto& entry : std::filesystem::directory_iterator(m_configDir, scanEc)) {
      if (entry.path().extension() != ".toml") {
        continue;
      }
      std::error_code symlinkEc;
      if (!entry.is_symlink(symlinkEc) || symlinkEc) {
        continue;
      }
      std::error_code canonEc;
      const auto real = std::filesystem::canonical(entry.path(), canonEc);
      if (canonEc) {
        continue;
      }
      const auto realDir = real.parent_path().string();
      const auto realName = real.filename().string();
      // inotify_add_watch is idempotent per inode — if realDir == m_configDir the
      // existing watch descriptor is returned and we simply record the extra name.
      const int wd =
          inotify_add_watch(m_inotifyFd, realDir.c_str(), IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE);
      if (wd >= 0) {
        m_symlinkDirWds[wd].push_back(realName);
        kLog.debug("watching symlink target {} in {}", realName, realDir);
      }
    }
  }

  // Also watch the state dir for overrides.toml edits (external writes).
  if (!m_overridesPath.empty()) {
    const auto overridesDir = std::filesystem::path(m_overridesPath).parent_path().string();
    m_overridesWatchWd =
        inotify_add_watch(m_inotifyFd, overridesDir.c_str(), IN_MODIFY | IN_CLOSE_WRITE | IN_CREATE | IN_MOVED_TO);
    if (m_overridesWatchWd < 0) {
      kLog.warn("inotify_add_watch failed for {}, overrides reload disabled", overridesDir);
    } else {
      kLog.debug("watching {} for changes", overridesDir);
    }
  }
}

void ConfigService::loadOverridesFromFile() {
  m_overridesTable = toml::table{};
  m_defaultWallpaperPath.clear();
  m_monitorWallpaperPaths.clear();

  if (m_overridesPath.empty() || !std::filesystem::exists(m_overridesPath)) {
    return;
  }

  kLog.info("loading {}", m_overridesPath);
  try {
    m_overridesTable = toml::parse_file(m_overridesPath);
  } catch (const toml::parse_error& e) {
    kLog.warn("parse error in {}: {}", m_overridesPath, e.what());
    m_overridesTable = toml::table{};
    return;
  }
  extractWallpaperFromOverrides();
}

void ConfigService::extractWallpaperFromOverrides() {
  if (auto* wpDefault = m_overridesTable["wallpaper"]["default"].as_table()) {
    if (auto v = (*wpDefault)["path"].value<std::string>()) {
      m_defaultWallpaperPath = *v;
    }
  }
  if (auto* monitors = m_overridesTable["wallpaper"]["monitors"].as_table()) {
    for (const auto& [key, value] : *monitors) {
      if (auto* monTbl = value.as_table()) {
        if (auto v = (*monTbl)["path"].value<std::string>()) {
          m_monitorWallpaperPaths[std::string(key.str())] = *v;
        }
      }
    }
  }
}

bool ConfigService::writeOverridesToFile() {
  if (m_overridesPath.empty()) {
    return false;
  }
  const std::string tmpPath = m_overridesPath + ".tmp";
  {
    std::ofstream out(tmpPath, std::ios::trunc);
    if (!out.is_open()) {
      return false;
    }
    out << m_overridesTable;
    if (!out.good()) {
      return false;
    }
  }
  std::error_code ec;
  std::filesystem::rename(tmpPath, m_overridesPath, ec);
  if (ec) {
    std::filesystem::remove(tmpPath, ec);
    return false;
  }
  return true;
}

void ConfigService::deepMerge(toml::table& base, const toml::table& overlay) {
  for (const auto& [k, v] : overlay) {
    if (const auto* overlayTbl = v.as_table()) {
      if (auto* baseNode = base.get(k)) {
        if (auto* baseTbl = baseNode->as_table()) {
          deepMerge(*baseTbl, *overlayTbl);
          continue;
        }
      }
    }
    // Tables-over-non-tables, non-tables, and arrays: overlay replaces base wholesale.
    base.insert_or_assign(k, v);
  }
}

void ConfigService::seedBuiltinWidgets(Config& config) {
  // Built-in named widget instances — act as defaults that [widget.*] entries override.
  auto seed = [&](const char* name, WidgetConfig wc) { config.widgets.emplace(name, std::move(wc)); };

  WidgetConfig cpu;
  cpu.type = "sysmon";
  cpu.settings["stat"] = std::string("cpu_usage");
  seed("cpu", std::move(cpu));

  WidgetConfig temp;
  temp.type = "sysmon";
  temp.settings["stat"] = std::string("cpu_temp");
  seed("temp", std::move(temp));

  WidgetConfig ram;
  ram.type = "sysmon";
  ram.settings["stat"] = std::string("ram_used");
  seed("ram", std::move(ram));

  WidgetConfig date;
  date.type = "clock";
  date.settings["format"] = std::string("{:%a %d %b}");
  seed("date", std::move(date));

  WidgetConfig media;
  media.type = "media";
  media.settings["max_length"] = 200.0;
  media.settings["art_size"] = 16.0;
  seed("media", std::move(media));

  WidgetConfig keyboardLayout;
  keyboardLayout.type = "keyboard_layout";
  keyboardLayout.settings["cycle_command"] = std::string("");
  seed("keyboard_layout", std::move(keyboardLayout));

  WidgetConfig lockKeys;
  lockKeys.type = "lock_keys";
  lockKeys.settings["show_caps_lock"] = true;
  lockKeys.settings["show_num_lock"] = true;
  lockKeys.settings["show_scroll_lock"] = false;
  lockKeys.settings["hide_when_off"] = false;
  lockKeys.settings["display"] = std::string("short");
  seed("lock_keys", std::move(lockKeys));

  WidgetConfig spacer;
  spacer.type = "spacer";
  seed("spacer", std::move(spacer));
}

void ConfigService::loadAll() {
  m_config = Config{};
  seedBuiltinWidgets(m_config);

  // Collect all *.toml files in the config dir, sorted alphabetically.
  std::vector<std::filesystem::path> files;
  if (!m_configDir.empty()) {
    std::error_code ec;
    if (std::filesystem::is_directory(m_configDir, ec)) {
      for (const auto& entry : std::filesystem::directory_iterator(m_configDir, ec)) {
        if (entry.is_regular_file() && entry.path().extension() == ".toml") {
          files.push_back(entry.path());
        }
      }
    }
  }
  std::sort(files.begin(), files.end());

  toml::table merged;
  std::string firstError;

  for (const auto& path : files) {
    try {
      auto tbl = toml::parse_file(path.string());
      deepMerge(merged, tbl);
      kLog.info("loaded {}", path.string());
    } catch (const toml::parse_error& e) {
      const auto& src = e.source();
      kLog.warn("parse error in {} at line {}, column {}: {}", path.filename().string(), src.begin.line,
                src.begin.column, e.description());
      if (firstError.empty()) {
        firstError = std::format("{} line {}, column {}: {}", path.filename().string(), src.begin.line,
                                 src.begin.column, e.description());
      }
    }
  }

  // Apply the app-writable overrides overlay last — sidecar wins.
  deepMerge(merged, m_overridesTable);

  if (files.empty() && m_overridesTable.empty()) {
    kLog.info("no config files found, using defaults");
    m_config.idle.behaviors.push_back(IdleBehaviorConfig{
        .name = "lock",
        .enabled = false,
        .timeoutSeconds = 660,
        .command = "noctalia:lock",
    });
    m_config.bars.push_back(BarConfig{});
    return;
  }

  std::string semanticError;
  try {
    parseTable(merged);
  } catch (const std::exception& e) {
    semanticError = e.what();
    kLog.warn("config parse error: {}", semanticError);
  }

  const std::string parseError = !firstError.empty() ? firstError : semanticError;
  if (parseError.empty()) {
    // Dismiss any previous config-error notification.
    if (m_notificationManager != nullptr && m_configErrorNotificationId != 0) {
      m_notificationManager->close(m_configErrorNotificationId);
      m_configErrorNotificationId = 0;
    }
    m_pendingError.clear();
  } else {
    if (m_notificationManager != nullptr) {
      if (m_configErrorNotificationId != 0) {
        m_notificationManager->close(m_configErrorNotificationId);
      }
      m_configErrorNotificationId =
          m_notificationManager->addInternal("Noctalia", "Config parse error", parseError, Urgency::Critical, 0);
    } else {
      m_pendingError = parseError;
    }
  }
}

void ConfigService::parseTable(const toml::table& tbl) {
  // Parse [bar.*] named subtables
  if (auto* barTblMap = tbl["bar"].as_table()) {
    for (const auto& [barName, barNode] : *barTblMap) {
      auto* barTbl = barNode.as_table();
      if (barTbl == nullptr) {
        continue;
      }

      BarConfig bar;
      bar.name = std::string(barName.str());
      if (auto v = (*barTbl)["position"].value<std::string>())
        bar.position = *v;
      if (auto v = (*barTbl)["enabled"].value<bool>())
        bar.enabled = *v;
      if (auto v = (*barTbl)["auto_hide"].value<bool>())
        bar.autoHide = *v;
      if (auto v = (*barTbl)["reserve_space"].value<bool>())
        bar.reserveSpace = *v;
      if (auto v = (*barTbl)["thickness"].value<int64_t>())
        bar.thickness = std::clamp(static_cast<std::int32_t>(*v), 10, 300);
      if (auto v = (*barTbl)["background_opacity"].value<double>())
        bar.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
      if (auto v = (*barTbl)["radius"].value<int64_t>()) {
        const auto r = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
        bar.radius = r;
        bar.radiusTopLeft = r;
        bar.radiusTopRight = r;
        bar.radiusBottomLeft = r;
        bar.radiusBottomRight = r;
      }
      if (auto v = (*barTbl)["radius_top_left"].value<int64_t>())
        bar.radiusTopLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["radius_top_right"].value<int64_t>())
        bar.radiusTopRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["radius_bottom_left"].value<int64_t>())
        bar.radiusBottomLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["radius_bottom_right"].value<int64_t>())
        bar.radiusBottomRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
      if (auto v = (*barTbl)["margin_h"].value<int64_t>())
        bar.marginH = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["margin_v"].value<int64_t>())
        bar.marginV = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["padding"].value<int64_t>())
        bar.padding = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["widget_spacing"].value<int64_t>())
        bar.widgetSpacing = static_cast<std::int32_t>(*v);
      if (auto v = (*barTbl)["shadow_blur"].value<int64_t>())
        bar.shadowBlur = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
      if (auto v = (*barTbl)["shadow_offset_x"].value<int64_t>())
        bar.shadowOffsetX = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
      if (auto v = (*barTbl)["shadow_offset_y"].value<int64_t>())
        bar.shadowOffsetY = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
      if (auto v = (*barTbl)["background_blur"].value<bool>())
        bar.backgroundBlur = *v;
      if (auto v = (*barTbl)["scale"].value<double>())
        bar.scale = std::clamp(static_cast<float>(*v), 0.5f, 4.0f);
      if (auto* n = (*barTbl)["start"].as_array())
        bar.startWidgets = readStringArray(*n);
      if (auto* n = (*barTbl)["center"].as_array())
        bar.centerWidgets = readStringArray(*n);
      if (auto* n = (*barTbl)["end"].as_array())
        bar.endWidgets = readStringArray(*n);

      if (auto v = (*barTbl)["capsule"].value<bool>()) {
        bar.widgetCapsuleDefault = *v;
      }
      if (auto fillStr = (*barTbl)["capsule_fill"].value<std::string>()) {
        bar.widgetCapsuleFill = themeColorFromCapsuleString(*fillStr);
      } else if (auto colorStr = (*barTbl)["capsule_color"].value<std::string>()) {
        bar.widgetCapsuleFill = themeColorFromCapsuleString(*colorStr);
      }
      if (auto fgStr = (*barTbl)["capsule_foreground"].value<std::string>()) {
        bar.widgetCapsuleForeground = themeColorFromCapsuleString(*fgStr);
      } else if (auto legacyInk = (*barTbl)["capsule_ink"].value<std::string>()) {
        bar.widgetCapsuleForeground = themeColorFromCapsuleString(*legacyInk);
      }
      if (auto v = (*barTbl)["capsule_padding"].value<double>()) {
        bar.widgetCapsulePadding = std::clamp(static_cast<float>(*v), 0.0f, 48.0f);
      }
      if (auto v = (*barTbl)["capsule_opacity"].value<double>()) {
        bar.widgetCapsuleOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
      }
      if (barTbl->contains("capsule_border")) {
        bar.widgetCapsuleBorderSpecified = true;
        std::string borderStr;
        if (auto v = (*barTbl)["capsule_border"].value<std::string>()) {
          borderStr = *v;
        }
        bar.widgetCapsuleBorder = optionalCapsuleBorder(borderStr);
      }
      if (auto widgetColorStr = (*barTbl)["color"].value<std::string>()) {
        bar.widgetColor = themeColorFromCapsuleString(*widgetColorStr);
      }

      // Parse [bar.<name>.monitor.*] overrides — insertion order preserved by toml++
      if (auto* monTblMap = (*barTbl)["monitor"].as_table()) {
        for (const auto& [monName, monNode] : *monTblMap) {
          auto* monTbl = monNode.as_table();
          if (monTbl == nullptr) {
            continue;
          }

          BarMonitorOverride ovr;
          if (auto v = (*monTbl)["match"].value<std::string>()) {
            ovr.match = *v;
          } else {
            ovr.match = std::string(monName.str()); // key is the match if not explicit
          }

          if (auto v = (*monTbl)["enabled"].value<bool>())
            ovr.enabled = *v;
          if (auto v = (*monTbl)["auto_hide"].value<bool>())
            ovr.autoHide = *v;
          if (auto v = (*monTbl)["reserve_space"].value<bool>())
            ovr.reserveSpace = *v;
          if (auto v = (*monTbl)["thickness"].value<int64_t>())
            ovr.thickness = std::clamp(static_cast<std::int32_t>(*v), 10, 300);
          if (auto v = (*monTbl)["background_opacity"].value<double>())
            ovr.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
          if (auto v = (*monTbl)["radius"].value<int64_t>())
            ovr.radius = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_top_left"].value<int64_t>())
            ovr.radiusTopLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_top_right"].value<int64_t>())
            ovr.radiusTopRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_bottom_left"].value<int64_t>())
            ovr.radiusBottomLeft = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["radius_bottom_right"].value<int64_t>())
            ovr.radiusBottomRight = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
          if (auto v = (*monTbl)["margin_h"].value<int64_t>())
            ovr.marginH = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["margin_v"].value<int64_t>())
            ovr.marginV = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["padding"].value<int64_t>())
            ovr.padding = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["widget_spacing"].value<int64_t>())
            ovr.widgetSpacing = static_cast<std::int32_t>(*v);
          if (auto v = (*monTbl)["scale"].value<double>())
            ovr.scale = std::clamp(static_cast<float>(*v), 0.5f, 4.0f);
          if (auto v = (*monTbl)["shadow_blur"].value<int64_t>())
            ovr.shadowBlur = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
          if (auto v = (*monTbl)["shadow_offset_x"].value<int64_t>())
            ovr.shadowOffsetX = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
          if (auto v = (*monTbl)["shadow_offset_y"].value<int64_t>())
            ovr.shadowOffsetY = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
          if (auto v = (*monTbl)["background_blur"].value<bool>())
            ovr.backgroundBlur = *v;
          if (auto* n = (*monTbl)["start"].as_array())
            ovr.startWidgets = readStringArray(*n);
          if (auto* n = (*monTbl)["center"].as_array())
            ovr.centerWidgets = readStringArray(*n);
          if (auto* n = (*monTbl)["end"].as_array())
            ovr.endWidgets = readStringArray(*n);

          if (auto v = (*monTbl)["capsule"].value<bool>()) {
            ovr.widgetCapsuleDefault = *v;
          }
          if (auto fillStr = (*monTbl)["capsule_fill"].value<std::string>()) {
            ovr.widgetCapsuleFill = *fillStr;
          } else if (auto colorStr = (*monTbl)["capsule_color"].value<std::string>()) {
            ovr.widgetCapsuleFill = *colorStr;
          }
          if (auto fgStr = (*monTbl)["capsule_foreground"].value<std::string>()) {
            ovr.widgetCapsuleForeground = *fgStr;
          } else if (auto legacyInk = (*monTbl)["capsule_ink"].value<std::string>()) {
            ovr.widgetCapsuleForeground = *legacyInk;
          }
          if (auto v = (*monTbl)["capsule_padding"].value<double>()) {
            ovr.widgetCapsulePadding = *v;
          }
          if (auto v = (*monTbl)["capsule_opacity"].value<double>()) {
            ovr.widgetCapsuleOpacity = *v;
          }
          if (monTbl->contains("capsule_border")) {
            std::string borderStr;
            if (auto v = (*monTbl)["capsule_border"].value<std::string>()) {
              borderStr = *v;
            }
            ovr.widgetCapsuleBorder = borderStr;
          }
          if (auto cStr = (*monTbl)["color"].value<std::string>()) {
            ovr.widgetColor = *cStr;
          }

          bar.monitorOverrides.push_back(std::move(ovr));
        }
      }

      m_config.bars.push_back(std::move(bar));
    }
  }

  // Parse [widget.*] — named widget instances with per-widget settings
  if (auto* widgetTbl = tbl["widget"].as_table()) {
    for (const auto& [name, node] : *widgetTbl) {
      auto* entryTbl = node.as_table();
      if (entryTbl == nullptr) {
        continue;
      }

      WidgetConfig wc;
      if (auto v = (*entryTbl)["type"].value<std::string>()) {
        wc.type = *v;
      } else {
        wc.type = std::string(name.str());
      }

      for (const auto& [key, val] : *entryTbl) {
        if (key == "type") {
          continue;
        }
        if (auto* s = val.as_string()) {
          wc.settings[std::string(key.str())] = s->get();
        } else if (auto* i = val.as_integer()) {
          wc.settings[std::string(key.str())] = i->get();
        } else if (auto* f = val.as_floating_point()) {
          wc.settings[std::string(key.str())] = f->get();
        } else if (auto* b = val.as_boolean()) {
          wc.settings[std::string(key.str())] = b->get();
        } else if (auto* arr = val.as_array()) {
          std::vector<std::string> list;
          list.reserve(arr->size());
          for (const auto& item : *arr) {
            if (auto v = item.value<std::string>()) {
              list.push_back(*v);
            }
          }
          wc.settings[std::string(key.str())] = std::move(list);
        }
      }

      m_config.widgets[std::string(name.str())] = std::move(wc);
    }
  }

  // Parse [shell]
  if (auto* shellTbl = tbl["shell"].as_table()) {
    auto& shell = m_config.shell;
    if (auto v = (*shellTbl)["ui_scale"].value<double>()) {
      shell.uiScale = std::clamp(static_cast<float>(*v), 0.5f, 4.0f);
    }
    if (auto v = (*shellTbl)["font_family"].value<std::string>()) {
      shell.fontFamily = trim(*v);
      if (shell.fontFamily.empty()) {
        shell.fontFamily = "sans-serif";
      }
    }
    if (auto v = (*shellTbl)["lang"].value<std::string>()) {
      shell.lang = *v;
    }
    if (auto notificationsDbus = (*shellTbl)["notifications_dbus"].value<bool>()) {
      shell.notificationsDbus = *notificationsDbus;
    }
    if (auto polkitAgent = (*shellTbl)["polkit_agent"].value<bool>()) {
      shell.polkitAgent = *polkitAgent;
    }
    const auto parsePasswordMaskStyle = [](std::string_view raw) -> std::optional<PasswordMaskStyle> {
      const std::string style = toLower(trim(raw));
      if (style == "default" || style == "circle_filled" || style == "circle-filled" || style == "circle") {
        return PasswordMaskStyle::CircleFilled;
      }
      if (style == "random" || style == "random_icons" || style == "random-icons") {
        return PasswordMaskStyle::RandomIcons;
      }
      return std::nullopt;
    };
    if (auto passwordStyle = (*shellTbl)["password_style"].value<std::string>()) {
      if (const auto parsed = parsePasswordMaskStyle(*passwordStyle); parsed.has_value()) {
        shell.passwordMaskStyle = *parsed;
      }
    } else if (auto passwordMaskStyle = (*shellTbl)["password_mask_style"].value<std::string>()) {
      // Backward-compat alias for older configs.
      if (const auto parsed = parsePasswordMaskStyle(*passwordMaskStyle); parsed.has_value()) {
        shell.passwordMaskStyle = *parsed;
      }
    }
    if (const auto* animationTbl = (*shellTbl)["animation"].as_table()) {
      if (auto enabled = (*animationTbl)["enabled"].value<bool>()) {
        shell.animation.enabled = *enabled;
      }
      if (auto v = (*animationTbl)["speed"].value<double>()) {
        shell.animation.speed = std::clamp(static_cast<float>(*v), 0.05f, 4.0f);
      }
    }
    if (auto v = (*shellTbl)["avatar_path"].value<std::string>()) {
      shell.avatarPath = *v;
    }
    if (auto v = (*shellTbl)["clipboard_auto_paste"].value<std::string>()) {
      if (*v == "off") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::Off;
      } else if (*v == "auto") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::Auto;
      } else if (*v == "ctrl_v") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::CtrlV;
      } else if (*v == "ctrl_shift_v") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::CtrlShiftV;
      } else if (*v == "shift_insert") {
        shell.clipboardAutoPaste = ClipboardAutoPasteMode::ShiftInsert;
      }
    }
  }

  // Parse [theme]
  if (auto* themeTbl = tbl["theme"].as_table()) {
    auto& theme = m_config.theme;
    if (auto v = (*themeTbl)["source"].value<std::string>()) {
      if (*v == "builtin")
        theme.source = ThemeSource::Builtin;
      else if (*v == "wallpaper")
        theme.source = ThemeSource::Wallpaper;
      else if (*v == "community")
        theme.source = ThemeSource::Community;
    }
    if (auto builtinPalette = (*themeTbl)["builtin_palette"].value<std::string>()) {
      theme.builtinPalette = *builtinPalette;
    } else if (auto builtin = (*themeTbl)["builtin"].value<std::string>()) {
      theme.builtinPalette = *builtin;
    }
    if (auto v = (*themeTbl)["community_palette"].value<std::string>()) {
      theme.communityPalette = *v;
    }
    if (auto v = (*themeTbl)["wallpaper_scheme"].value<std::string>())
      theme.wallpaperScheme = *v;
    if (auto v = (*themeTbl)["mode"].value<std::string>()) {
      if (*v == "dark")
        theme.mode = ThemeMode::Dark;
      else if (*v == "light")
        theme.mode = ThemeMode::Light;
      else if (*v == "auto")
        theme.mode = ThemeMode::Auto;
    }
    if (const auto* templatesTbl = (*themeTbl)["templates"].as_table()) {
      auto& templates = theme.templates;
      if (auto v = (*templatesTbl)["enable_builtins"].value<bool>())
        templates.enableBuiltins = *v;
      if (auto v = (*templatesTbl)["enable_user_templates"].value<bool>())
        templates.enableUserTemplates = *v;
      if (auto v = (*templatesTbl)["user_config"].value<std::string>())
        templates.userConfig = *v;
      if (const auto* builtinIds = (*templatesTbl)["builtin_ids"].as_array()) {
        templates.builtinIds.clear();
        templates.builtinIds.reserve(builtinIds->size());
        for (const auto& item : *builtinIds) {
          if (const auto* id = item.as_string())
            templates.builtinIds.push_back(id->get());
        }
      }
    }
  }

  // Parse [wallpaper]
  if (auto* wpTbl = tbl["wallpaper"].as_table()) {
    auto& wp = m_config.wallpaper;
    if (auto v = (*wpTbl)["enabled"].value<bool>())
      wp.enabled = *v;
    if (auto v = (*wpTbl)["fill_mode"].value<std::string>()) {
      if (*v == "center")
        wp.fillMode = WallpaperFillMode::Center;
      else if (*v == "crop")
        wp.fillMode = WallpaperFillMode::Crop;
      else if (*v == "fit")
        wp.fillMode = WallpaperFillMode::Fit;
      else if (*v == "stretch")
        wp.fillMode = WallpaperFillMode::Stretch;
      else if (*v == "repeat")
        wp.fillMode = WallpaperFillMode::Repeat;
    }
    auto parseTransition = [](const std::string& s) -> std::optional<WallpaperTransition> {
      if (s == "fade")
        return WallpaperTransition::Fade;
      if (s == "wipe")
        return WallpaperTransition::Wipe;
      if (s == "disc")
        return WallpaperTransition::Disc;
      if (s == "stripes")
        return WallpaperTransition::Stripes;
      if (s == "zoom")
        return WallpaperTransition::Zoom;
      if (s == "honeycomb")
        return WallpaperTransition::Honeycomb;
      return std::nullopt;
    };
    if (auto* arr = (*wpTbl)["transition"].as_array()) {
      wp.transitions.clear();
      for (const auto& item : *arr) {
        if (auto s = item.value<std::string>()) {
          if (auto t = parseTransition(*s))
            wp.transitions.push_back(*t);
        }
      }
      if (wp.transitions.empty())
        wp.transitions.push_back(WallpaperTransition::Fade);
    }
    if (auto v = (*wpTbl)["transition_duration"].value<double>())
      wp.transitionDurationMs = std::clamp(static_cast<float>(*v), 100.0f, 30000.0f);
    if (auto v = (*wpTbl)["edge_smoothness"].value<double>())
      wp.edgeSmoothness = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*wpTbl)["directory"].value<std::string>())
      wp.directory = *v;
    if (auto v = (*wpTbl)["directory_light"].value<std::string>())
      wp.directoryLight = *v;
    if (auto v = (*wpTbl)["directory_dark"].value<std::string>())
      wp.directoryDark = *v;

    if (auto* monTblMap = (*wpTbl)["monitor"].as_table()) {
      for (const auto& [monName, monNode] : *monTblMap) {
        auto* monTbl = monNode.as_table();
        if (monTbl == nullptr) {
          continue;
        }
        WallpaperMonitorOverride ovr;
        if (auto v = (*monTbl)["match"].value<std::string>())
          ovr.match = *v;
        else
          ovr.match = std::string(monName.str());
        if (auto v = (*monTbl)["enabled"].value<bool>())
          ovr.enabled = *v;
        if (auto v = (*monTbl)["directory"].value<std::string>())
          ovr.directory = *v;
        if (auto v = (*monTbl)["directory_light"].value<std::string>())
          ovr.directoryLight = *v;
        if (auto v = (*monTbl)["directory_dark"].value<std::string>())
          ovr.directoryDark = *v;
        wp.monitorOverrides.push_back(std::move(ovr));
      }
    }
  }

  // Parse [overview]
  if (auto* ovTbl = tbl["overview"].as_table()) {
    auto& ov = m_config.overview;
    if (auto v = (*ovTbl)["enabled"].value<bool>())
      ov.enabled = *v;
    if (auto v = (*ovTbl)["unload_when_not_in_use"].value<bool>())
      ov.unloadWhenNotInUse = *v;
    if (auto v = (*ovTbl)["blur_intensity"].value<double>())
      ov.blurIntensity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*ovTbl)["tint_intensity"].value<double>())
      ov.tintIntensity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
  }

  // Parse [osd]
  if (auto* osdTbl = tbl["osd"].as_table()) {
    auto& osd = m_config.osd;
    if (auto v = (*osdTbl)["position"].value<std::string>())
      osd.position = *v;
  }

  if (auto* notifTbl = tbl["notification"].as_table()) {
    auto& notif = m_config.notification;
    if (auto v = (*notifTbl)["background_opacity"].value<double>())
      notif.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*notifTbl)["background_blur"].value<bool>())
      notif.backgroundBlur = *v;
  }

  // Parse [dock]
  if (auto* dockTbl = tbl["dock"].as_table()) {
    auto& dock = m_config.dock;
    if (auto v = (*dockTbl)["enabled"].value<bool>())
      dock.enabled = *v;
    if (auto v = (*dockTbl)["active_monitor_only"].value<bool>())
      dock.activeMonitorOnly = *v;
    if (auto v = (*dockTbl)["position"].value<std::string>())
      dock.position = *v;
    if (auto v = (*dockTbl)["icon_size"].value<int64_t>())
      dock.iconSize = std::clamp(static_cast<std::int32_t>(*v), 16, 256);
    if (auto v = (*dockTbl)["padding"].value<int64_t>())
      dock.padding = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["item_spacing"].value<int64_t>())
      dock.itemSpacing = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["background_opacity"].value<double>())
      dock.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*dockTbl)["radius"].value<int64_t>())
      dock.radius = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
    if (auto v = (*dockTbl)["margin_h"].value<int64_t>())
      dock.marginH = std::clamp(static_cast<std::int32_t>(*v), 0, 500);
    if (auto v = (*dockTbl)["margin_v"].value<int64_t>())
      dock.marginV = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["shadow_blur"].value<int64_t>())
      dock.shadowBlur = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
    if (auto v = (*dockTbl)["shadow_offset_x"].value<int64_t>())
      dock.shadowOffsetX = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
    if (auto v = (*dockTbl)["shadow_offset_y"].value<int64_t>())
      dock.shadowOffsetY = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
    if (auto v = (*dockTbl)["background_blur"].value<bool>())
      dock.backgroundBlur = *v;
    if (auto v = (*dockTbl)["show_running"].value<bool>())
      dock.showRunning = *v;
    if (auto v = (*dockTbl)["auto_hide"].value<bool>())
      dock.autoHide = *v;
    if (auto v = (*dockTbl)["reserve_space"].value<bool>())
      dock.reserveSpace = *v;
    if (auto v = (*dockTbl)["active_scale"].value<double>())
      dock.activeScale = std::clamp(static_cast<float>(*v), 0.1f, 1.75f);
    if (auto v = (*dockTbl)["inactive_scale"].value<double>())
      dock.inactiveScale = std::clamp(static_cast<float>(*v), 0.1f, 1.0f);
    if (auto v = (*dockTbl)["active_opacity"].value<double>())
      dock.activeOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*dockTbl)["inactive_opacity"].value<double>())
      dock.inactiveOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (auto v = (*dockTbl)["show_instance_count"].value<bool>())
      dock.showInstanceCount = *v;
    if (auto* arr = (*dockTbl)["pinned"].as_array())
      dock.pinned = readStringArray(*arr);
  }

  // Parse [desktop_widgets]
  if (auto* desktopWidgetsTbl = tbl["desktop_widgets"].as_table()) {
    auto& desktopWidgets = m_config.desktopWidgets;
    if (auto v = (*desktopWidgetsTbl)["enabled"].value<bool>()) {
      desktopWidgets.enabled = *v;
    }
  }

  // Parse [weather]
  if (auto* weatherTbl = tbl["weather"].as_table()) {
    auto& weather = m_config.weather;
    if (auto v = (*weatherTbl)["enabled"].value<bool>())
      weather.enabled = *v;
    if (auto v = (*weatherTbl)["auto_locate"].value<bool>())
      weather.autoLocate = *v;
    if (auto v = (*weatherTbl)["address"].value<std::string>())
      weather.address = *v;
    if (auto v = (*weatherTbl)["refresh_minutes"].value<int64_t>())
      weather.refreshMinutes = static_cast<std::int32_t>(*v);
    if (auto v = (*weatherTbl)["unit"].value<std::string>())
      weather.unit = *v;
  }

  // Parse [audio]
  if (auto* audioTbl = tbl["audio"].as_table()) {
    auto& audio = m_config.audio;
    if (auto v = (*audioTbl)["enable_overdrive"].value<bool>()) {
      audio.enableOverdrive = *v;
    }
  }

  // Parse [brightness]
  if (auto* brightnessTbl = tbl["brightness"].as_table()) {
    auto& brightness = m_config.brightness;
    if (auto v = (*brightnessTbl)["enable_ddcutil"].value<bool>()) {
      brightness.enableDdcutil = *v;
    }
    if (auto* mmidArr = (*brightnessTbl)["ignore_mmids"].as_array()) {
      for (const auto& item : *mmidArr) {
        if (auto s = item.value<std::string>()) {
          brightness.ddcutilIgnoreMmids.push_back(*s);
        }
      }
    }
    if (auto* monitorTblMap = (*brightnessTbl)["monitor"].as_table()) {
      for (const auto& [name, node] : *monitorTblMap) {
        auto* entryTbl = node.as_table();
        if (entryTbl == nullptr) {
          continue;
        }

        BrightnessMonitorOverride override;
        override.match = std::string(name.str());

        if (auto v = (*entryTbl)["match"].value<std::string>()) {
          override.match = *v;
        }
        if (auto v = (*entryTbl)["backend"].value<std::string>()) {
          if (const auto parsed = parseBrightnessBackendPreference(*v); parsed.has_value()) {
            override.backend = *parsed;
          } else {
            kLog.warn("invalid brightness backend '{}' for monitor override '{}'", *v, override.match);
          }
        }

        brightness.monitorOverrides.push_back(std::move(override));
      }
    }
  }

  // Parse [keybinds]
  if (auto* keybindsTbl = tbl["keybinds"].as_table()) {
    auto& keybinds = m_config.keybinds;

    auto parseAction = [&](std::string_view key, std::vector<KeyChord>& out) {
      out.clear();
      if (const auto* node = keybindsTbl->get(key)) {
        if (const auto v = node->value<std::string>()) {
          try {
            if (const auto chord = parseKeyChord(*v); chord.has_value()) {
              out.push_back(*chord);
            } else {
              kLog.warn("invalid keybind chord for [{}] {} = \"{}\"", "keybinds", key, *v);
            }
          } catch (const std::exception& e) {
            throw std::runtime_error(std::format("keybinds.{}: {}", key, e.what()));
          }
          return;
        }
        if (const auto* arr = node->as_array()) {
          for (const auto& item : *arr) {
            if (const auto v = item.value<std::string>()) {
              try {
                if (const auto chord = parseKeyChord(*v); chord.has_value()) {
                  out.push_back(*chord);
                } else {
                  kLog.warn("invalid keybind chord for [{}] {} item = \"{}\"", "keybinds", key, *v);
                }
              } catch (const std::exception& e) {
                throw std::runtime_error(std::format("keybinds.{}: {}", key, e.what()));
              }
            }
          }
        }
      }
    };

    parseAction("validate", keybinds.validate);
    parseAction("cancel", keybinds.cancel);
    parseAction("left", keybinds.left);
    parseAction("right", keybinds.right);
    parseAction("up", keybinds.up);
    parseAction("down", keybinds.down);
  }

  // Parse [nightlight]
  if (auto* nightlightTbl = tbl["nightlight"].as_table()) {
    auto& nightlight = m_config.nightlight;
    if (auto v = (*nightlightTbl)["enabled"].value<bool>()) {
      nightlight.enabled = *v;
    }
    if (auto v = (*nightlightTbl)["force"].value<bool>()) {
      nightlight.force = *v;
    }
    if (auto v = (*nightlightTbl)["use_weather_location"].value<bool>()) {
      nightlight.useWeatherLocation = *v;
    }
    if (auto v = (*nightlightTbl)["start_time"].value<std::string>()) {
      nightlight.startTime = *v;
    }
    if (auto v = (*nightlightTbl)["stop_time"].value<std::string>()) {
      nightlight.stopTime = *v;
    }
    if (auto v = (*nightlightTbl)["latitude"].value<double>()) {
      nightlight.latitude = *v;
    }
    if (auto v = (*nightlightTbl)["longitude"].value<double>()) {
      nightlight.longitude = *v;
    }
    if (auto v = (*nightlightTbl)["temperature_day"].value<int64_t>()) {
      nightlight.dayTemperature = std::clamp(static_cast<std::int32_t>(*v), 1000, 25000);
    }
    if (auto v = (*nightlightTbl)["temperature_night"].value<int64_t>()) {
      nightlight.nightTemperature = std::clamp(static_cast<std::int32_t>(*v), 1000, 25000);
    }
  }

  // Parse [hooks]
  if (auto* hooksTbl = tbl["hooks"].as_table()) {
    auto& hooks = m_config.hooks;
    for (const auto& [name, node] : *hooksTbl) {
      const std::string_view keyView{name.str()};
      if (keyView == "battery_low_percent_threshold") {
        if (auto v = node.value<int64_t>()) {
          hooks.batteryLowPercentThreshold =
              static_cast<std::int32_t>(std::clamp(*v, static_cast<std::int64_t>(0), static_cast<std::int64_t>(100)));
        }
        continue;
      }
      if (const auto kind = hookKindFromKey(keyView)) {
        setHookCommandsFromNode(node, hooks.commands[static_cast<std::size_t>(*kind)]);
      }
    }
  }

  // Parse [idle.behavior.*]
  if (auto* idleTbl = tbl["idle"].as_table()) {
    if (auto* behaviorTbl = (*idleTbl)["behavior"].as_table()) {
      for (const auto& [name, node] : *behaviorTbl) {
        auto* entryTbl = node.as_table();
        if (entryTbl == nullptr) {
          continue;
        }

        IdleBehaviorConfig behavior;
        behavior.name = std::string(name.str());

        if (auto v = (*entryTbl)["enabled"].value<bool>()) {
          behavior.enabled = *v;
        }
        if (auto v = (*entryTbl)["timeout"].value<int64_t>()) {
          behavior.timeoutSeconds = static_cast<std::int32_t>(*v);
        }
        if (auto v = (*entryTbl)["command"].value<std::string>()) {
          behavior.command = *v;
        }

        m_config.idle.behaviors.push_back(std::move(behavior));
      }
    }
  }

  if (m_config.bars.empty()) {
    kLog.info("no [bar.*] defined, using defaults");
    m_config.bars.push_back(BarConfig{});
  }

  kLog.info("{} bar(s) defined", m_config.bars.size());
  kLog.info("idle behaviors={}", m_config.idle.behaviors.size());
  std::size_t hookKindsUsed = 0;
  for (const auto& cmds : m_config.hooks.commands) {
    if (!cmds.empty()) {
      ++hookKindsUsed;
    }
  }
  kLog.info("hooks kinds with commands={} battery_low_threshold={}%", hookKindsUsed,
            m_config.hooks.batteryLowPercentThreshold);
}

bool ConfigService::matchesKeybind(KeybindAction action, std::uint32_t sym, std::uint32_t modifiers) const {
  const auto& configured = keybindSet(m_config.keybinds, action);
  const auto active = configured.empty() ? defaultKeybindSet(action) : configured;
  return std::any_of(active.begin(), active.end(), [sym, modifiers](const KeyChord& chord) {
    return chord.sym == sym && chord.modifiers == modifiers;
  });
}

// ── WidgetConfig accessors ───────────────────────────────────────────────────

std::string WidgetConfig::getString(const std::string& key, const std::string& fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::string>(&it->second)) {
    return *v;
  }
  return fallback;
}

std::vector<std::string> WidgetConfig::getStringList(const std::string& key,
                                                     const std::vector<std::string>& fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::vector<std::string>>(&it->second)) {
    return *v;
  }
  if (const auto* v = std::get_if<std::string>(&it->second)) {
    return {*v};
  }
  return fallback;
}

std::int64_t WidgetConfig::getInt(const std::string& key, std::int64_t fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<std::int64_t>(&it->second)) {
    return *v;
  }
  return fallback;
}

double WidgetConfig::getDouble(const std::string& key, double fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<double>(&it->second)) {
    return *v;
  }
  // Allow int → double promotion
  if (const auto* v = std::get_if<std::int64_t>(&it->second)) {
    return static_cast<double>(*v);
  }
  return fallback;
}

bool WidgetConfig::getBool(const std::string& key, bool fallback) const {
  auto it = settings.find(key);
  if (it == settings.end()) {
    return fallback;
  }
  if (const auto* v = std::get_if<bool>(&it->second)) {
    return *v;
  }
  return fallback;
}

bool WidgetConfig::hasSetting(const std::string& key) const { return settings.find(key) != settings.end(); }

WidgetBarCapsuleSpec resolveWidgetBarCapsuleSpec(const BarConfig& bar, const WidgetConfig* widget) {
  WidgetBarCapsuleSpec spec{};
  const bool widgetHasCapsuleKey = widget != nullptr && widget->hasSetting("capsule");
  const bool widgetHasFillKey = widget != nullptr && widget->hasSetting("capsule_fill");
  const bool widgetHasColorKey = widget != nullptr && widget->hasSetting("capsule_color");
  const bool widgetHasBorderKey = widget != nullptr && widget->hasSetting("capsule_border");

  if (widgetHasCapsuleKey) {
    spec.enabled = widget->getBool("capsule", false);
  } else {
    spec.enabled = bar.widgetCapsuleDefault;
  }
  if (!spec.enabled) {
    return spec;
  }

  if (widgetHasFillKey) {
    spec.fill = themeColorFromCapsuleString(widget->getString("capsule_fill", ""));
  } else if (widgetHasColorKey) {
    spec.fill = themeColorFromCapsuleString(widget->getString("capsule_color", ""));
  } else {
    spec.fill = bar.widgetCapsuleFill;
  }

  if (widgetHasBorderKey) {
    spec.border = optionalCapsuleBorder(widget->getString("capsule_border", ""));
  } else if (bar.widgetCapsuleBorderSpecified) {
    spec.border = bar.widgetCapsuleBorder;
  } else {
    spec.border = std::nullopt;
  }

  spec.padding = bar.widgetCapsulePadding;
  if (widget != nullptr && widget->hasSetting("capsule_padding")) {
    spec.padding = std::clamp(
        static_cast<float>(widget->getDouble("capsule_padding", static_cast<double>(spec.padding))), 0.0f, 48.0f);
  }
  spec.opacity = bar.widgetCapsuleOpacity;
  if (widget != nullptr && widget->hasSetting("capsule_opacity")) {
    spec.opacity = std::clamp(
        static_cast<float>(widget->getDouble("capsule_opacity", static_cast<double>(spec.opacity))), 0.0f, 1.0f);
  }

  if (widget != nullptr && widget->hasSetting("capsule_foreground")) {
    spec.foreground = themeColorFromCapsuleString(widget->getString("capsule_foreground", ""));
  } else if (widget != nullptr && widget->hasSetting("capsule_ink")) {
    spec.foreground = themeColorFromCapsuleString(widget->getString("capsule_ink", ""));
  } else if (bar.widgetCapsuleForeground.has_value()) {
    spec.foreground = bar.widgetCapsuleForeground;
  } else {
    spec.foreground = std::nullopt;
  }
  return spec;
}

void ConfigService::registerIpc(IpcService& ipc) {
  ipc.registerHandler(
      "config-reload",
      [this](const std::string&) -> std::string {
        forceReload();
        return "ok\n";
      },
      "config-reload", "Reload the config file");
}
