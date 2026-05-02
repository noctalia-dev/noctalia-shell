#include "config/config_service.h"

#include "core/build_info.h"
#include "core/log.h"
#include "ipc/ipc_service.h"
#include "notification/notification_manager.h"
#include "util/file_utils.h"
#include "util/string_utils.h"
#include "wayland/wayland_connection.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <sys/inotify.h>
#include <unistd.h>
#include <vector>
#include <xkbcommon/xkbcommon.h>

namespace {

  std::string expandUserPathString(const std::string& path) {
    if (path.empty()) {
      return path;
    }
    return FileUtils::expandUserPath(path).string();
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

  std::optional<KeyChord> parseKeyChord(std::string_view rawSpec) {
    const std::string spec = StringUtils::trim(rawSpec);
    if (spec.empty()) {
      return std::nullopt;
    }

    std::vector<std::string> tokens;
    std::size_t start = 0;
    while (start <= spec.size()) {
      const std::size_t plus = spec.find('+', start);
      const std::size_t len = (plus == std::string::npos) ? (spec.size() - start) : (plus - start);
      const std::string token = StringUtils::trim(std::string_view(spec).substr(start, len));
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
      const std::string mod = StringUtils::toLower(tokens[i]);
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

    std::string keyName = StringUtils::toLower(tokens.back());
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
  constexpr const char* kInternalStateTable = "noctalia_state";
  constexpr const char* kSetupWizardCompletedKey = "setup_wizard_completed";

  std::vector<std::filesystem::path> sortedConfigTomlFiles(std::string_view configDir) {
    std::vector<std::filesystem::path> files;
    if (configDir.empty()) {
      return files;
    }

    std::error_code ec;
    if (!std::filesystem::is_directory(configDir, ec) || ec) {
      return files;
    }
    for (const auto& entry : std::filesystem::directory_iterator(configDir, ec)) {
      if (entry.is_regular_file() && entry.path().extension() == ".toml") {
        files.push_back(entry.path());
      }
    }
    std::sort(files.begin(), files.end());
    return files;
  }

  std::string readTextFile(const std::filesystem::path& path, std::string* error = nullptr) {
    std::ifstream in(path, std::ios::binary);
    if (!in.is_open()) {
      if (error != nullptr) {
        *error = "open failed";
      }
      return {};
    }

    std::ostringstream out;
    out << in.rdbuf();
    if (!in.good() && !in.eof()) {
      if (error != nullptr) {
        *error = "read failed";
      }
      return {};
    }
    if (error != nullptr) {
      error->clear();
    }
    return out.str();
  }

  std::string formatToml(const toml::table& table) {
    std::ostringstream out;
    out << toml::toml_formatter{table,
                                toml::toml_formatter::default_flags & ~toml::format_flags::allow_literal_strings};
    return out.str();
  }

  std::string utcTimestamp() {
    const auto now = std::chrono::system_clock::now();
    const std::time_t tt = std::chrono::system_clock::to_time_t(now);
    std::tm tm{};
    gmtime_r(&tt, &tm);

    std::ostringstream out;
    out << std::put_time(&tm, "%Y-%m-%dT%H:%M:%SZ");
    return out.str();
  }

  std::string relativeTo(const std::filesystem::path& path, const std::filesystem::path& base) {
    const auto relative = path.lexically_relative(base);
    if (!relative.empty()) {
      return relative.string();
    }
    return path.filename().string();
  }

  bool setupWizardCompletedFrom(const toml::table& table) {
    const auto* state = table[kInternalStateTable].as_table();
    if (state == nullptr) {
      return false;
    }
    return (*state)[kSetupWizardCompletedKey].value<bool>().value_or(false);
  }

  void stripInternalState(toml::table& table) { table.erase(kInternalStateTable); }

  ThemeColor themeColorFromRoleString(const std::string& raw) {
    const std::string trimmed = StringUtils::trim(raw);
    Color fixed;
    if (tryParseHexColor(trimmed, fixed)) {
      return fixedColor(fixed);
    }
    if (auto role = colorRoleFromToken(trimmed)) {
      return roleColor(*role);
    }
    kLog.warn("unknown theme color role \"{}\", using surface_variant", raw);
    return roleColor(ColorRole::SurfaceVariant);
  }

  std::optional<ThemeColor> optionalCapsuleBorder(const std::string& raw) {
    if (StringUtils::trim(raw).empty()) {
      return std::nullopt;
    }
    return themeColorFromRoleString(raw);
  }

} // namespace

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
  m_configDir = FileUtils::configDir();

  // Resolve settings.toml path; create the state dir eagerly so writes don't
  // race with directory creation later.
  if (auto dir = FileUtils::stateDir(); !dir.empty()) {
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    m_overridesPath = dir + "/settings.toml";
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

bool ConfigService::shouldRunSetupWizard() const {
  return !m_setupWizardCompleted && sortedConfigTomlFiles(m_configDir).empty() && m_overridesTable.empty();
}

std::string ConfigService::buildSupportReport() const {
  toml::table root;

  toml::table report;
  report.insert_or_assign("format_version", std::int64_t{1});
  report.insert_or_assign("generated_by", "noctalia");
  report.insert_or_assign("generated_at_utc", utcTimestamp());
  report.insert_or_assign("noctalia_version", std::string(noctalia::build_info::version()));
  report.insert_or_assign("git_revision", std::string(noctalia::build_info::revision()));
  root.insert_or_assign("report", std::move(report));

  toml::table paths;
  paths.insert_or_assign("config_dir", m_configDir);
  paths.insert_or_assign("settings_path", m_overridesPath);
  root.insert_or_assign("paths", std::move(paths));

  toml::table merged;
  toml::array sources;
  const auto configFiles = sortedConfigTomlFiles(m_configDir);
  for (std::size_t i = 0; i < configFiles.size(); ++i) {
    const auto& path = configFiles[i];

    toml::table source;
    source.insert_or_assign("kind", "declarative");
    source.insert_or_assign("load_order", static_cast<std::int64_t>(i));
    source.insert_or_assign("relative_path", relativeTo(path, m_configDir));
    source.insert_or_assign("path", path.string());

    std::string readError;
    source.insert_or_assign("content", readTextFile(path, &readError));
    if (!readError.empty()) {
      source.insert_or_assign("read_error", readError);
    } else {
      try {
        auto table = toml::parse_file(path.string());
        deepMerge(merged, table);
      } catch (const toml::parse_error& e) {
        source.insert_or_assign("parse_error", e.what());
      }
    }

    sources.push_back(std::move(source));
  }
  root.insert_or_assign("config_sources", std::move(sources));

  toml::table state;
  state.insert_or_assign("kind", "state");
  state.insert_or_assign("relative_path", "settings.toml");
  state.insert_or_assign("path", m_overridesPath);

  const bool settingsExists = !m_overridesPath.empty() && std::filesystem::exists(m_overridesPath);
  state.insert_or_assign("exists", settingsExists);
  if (settingsExists) {
    std::string readError;
    state.insert_or_assign("content", readTextFile(m_overridesPath, &readError));
    if (!readError.empty()) {
      state.insert_or_assign("read_error", readError);
    } else {
      try {
        auto table = toml::parse_file(m_overridesPath);
        stripInternalState(table);
        deepMerge(merged, table);
      } catch (const toml::parse_error& e) {
        state.insert_or_assign("parse_error", e.what());
      }
    }
  } else {
    state.insert_or_assign("content", "");
  }
  root.insert_or_assign("state_settings", std::move(state));

  toml::table mergedConfig;
  mergedConfig.insert_or_assign("content", formatToml(merged));
  root.insert_or_assign("merged_config", std::move(mergedConfig));

  return formatToml(root) + "\n";
}

std::string ConfigService::buildFlattenedConfig() const {
  toml::table merged;

  for (const auto& path : sortedConfigTomlFiles(m_configDir)) {
    try {
      auto table = toml::parse_file(path.string());
      deepMerge(merged, table);
    } catch (const toml::parse_error& e) {
      kLog.warn("skipping parse error in flattened config export {}: {}", path.filename().string(), e.description());
    }
  }

  if (!m_overridesPath.empty() && std::filesystem::exists(m_overridesPath)) {
    try {
      auto table = toml::parse_file(m_overridesPath);
      stripInternalState(table);
      deepMerge(merged, table);
    } catch (const toml::parse_error& e) {
      kLog.warn("skipping parse error in flattened config export {}: {}", m_overridesPath, e.description());
    }
  }

  return formatToml(merged) + "\n";
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
    if (ovr.shadow)
      resolved.shadow = *ovr.shadow;
    if (ovr.attachPanels)
      resolved.attachPanels = *ovr.attachPanels;
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
      resolved.widgetCapsuleFill = *ovr.widgetCapsuleFill;
    if (ovr.widgetCapsuleBorderSpecified) {
      resolved.widgetCapsuleBorderSpecified = true;
      resolved.widgetCapsuleBorder = ovr.widgetCapsuleBorder;
    }
    if (ovr.widgetCapsuleForeground) {
      resolved.widgetCapsuleForeground = *ovr.widgetCapsuleForeground;
    }
    if (ovr.widgetColor) {
      resolved.widgetColor = *ovr.widgetColor;
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

  // Also watch the state dir for settings.toml edits (external writes).
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
  m_setupWizardCompleted = false;

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
  m_setupWizardCompleted = setupWizardCompletedFrom(m_overridesTable);
  stripInternalState(m_overridesTable);
  extractWallpaperFromOverrides();
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

  const auto files = sortedConfigTomlFiles(m_configDir);

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

  m_configFileBarNames.clear();
  m_configFileMonitorOverrideNames.clear();
  if (auto* barTblMap = merged["bar"].as_table()) {
    for (const auto& [barName, barNode] : *barTblMap) {
      auto* barTbl = barNode.as_table();
      if (barTbl == nullptr) {
        continue;
      }
      const std::string barNameStr(barName.str());
      m_configFileBarNames.insert(barNameStr);
      if (auto* monTblMap = (*barTbl)["monitor"].as_table()) {
        auto& monitorNames = m_configFileMonitorOverrideNames[barNameStr];
        for (const auto& [monName, monNode] : *monTblMap) {
          auto* monTbl = monNode.as_table();
          if (monTbl == nullptr) {
            continue;
          }
          if (auto match = (*monTbl)["match"].value<std::string>()) {
            monitorNames.insert(*match);
          } else {
            monitorNames.insert(std::string(monName.str()));
          }
        }
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
        .command = "noctalia:screen-lock",
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
    std::vector<BarConfig> parsedBars;
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
      if (auto v = (*barTbl)["attach_panels"].value<bool>())
        bar.attachPanels = *v;
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
      if (auto v = (*barTbl)["shadow"].value<bool>())
        bar.shadow = *v;
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
        bar.widgetCapsuleFill = themeColorFromRoleString(*fillStr);
      }
      if (auto fgStr = (*barTbl)["capsule_foreground"].value<std::string>()) {
        bar.widgetCapsuleForeground = themeColorFromRoleString(*fgStr);
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
        bar.widgetColor = themeColorFromRoleString(*widgetColorStr);
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
          if (auto v = (*monTbl)["attach_panels"].value<bool>())
            ovr.attachPanels = *v;
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
          if (auto v = (*monTbl)["shadow"].value<bool>())
            ovr.shadow = *v;
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
            ovr.widgetCapsuleFill = themeColorFromRoleString(*fillStr);
          }
          if (auto fgStr = (*monTbl)["capsule_foreground"].value<std::string>()) {
            ovr.widgetCapsuleForeground = themeColorFromRoleString(*fgStr);
          }
          if (auto v = (*monTbl)["capsule_padding"].value<double>()) {
            ovr.widgetCapsulePadding = *v;
          }
          if (auto v = (*monTbl)["capsule_opacity"].value<double>()) {
            ovr.widgetCapsuleOpacity = *v;
          }
          if (monTbl->contains("capsule_border")) {
            ovr.widgetCapsuleBorderSpecified = true;
            std::string borderStr;
            if (auto v = (*monTbl)["capsule_border"].value<std::string>()) {
              borderStr = *v;
            }
            ovr.widgetCapsuleBorder = optionalCapsuleBorder(borderStr);
          }
          if (auto cStr = (*monTbl)["color"].value<std::string>()) {
            ovr.widgetColor = themeColorFromRoleString(*cStr);
          }

          bar.monitorOverrides.push_back(std::move(ovr));
        }
      }

      parsedBars.push_back(std::move(bar));
    }

    std::vector<std::string> order;
    if (auto* orderNode = (*barTblMap)["order"].as_array()) {
      order = readStringArray(*orderNode);
    }

    std::vector<bool> used(parsedBars.size(), false);
    for (const auto& orderedName : order) {
      for (std::size_t i = 0; i < parsedBars.size(); ++i) {
        if (!used[i] && parsedBars[i].name == orderedName) {
          used[i] = true;
          m_config.bars.push_back(std::move(parsedBars[i]));
          break;
        }
      }
    }

    for (std::size_t i = 0; i < parsedBars.size(); ++i) {
      if (!used[i]) {
        m_config.bars.push_back(std::move(parsedBars[i]));
      }
    }
  }

  // Parse [widget.*] — named widget instances with per-widget settings
  if (auto* widgetTbl = tbl["widget"].as_table()) {
    for (const auto& [name, node] : *widgetTbl) {
      auto* entryTbl = node.as_table();
      if (entryTbl == nullptr) {
        continue;
      }

      std::string widgetName(name.str());
      WidgetConfig wc;

      if (auto v = (*entryTbl)["type"].value<std::string>()) {
        wc.type = *v;
        if (auto it = m_config.widgets.find(widgetName); it != m_config.widgets.end() && it->second.type == wc.type) {
          wc.settings = it->second.settings;
        }
      } else if (auto it = m_config.widgets.find(widgetName); it != m_config.widgets.end()) {
        wc = it->second;
      } else {
        wc.type = widgetName;
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

      m_config.widgets[widgetName] = std::move(wc);
    }
  }

  // Parse [shell]
  if (auto* shellTbl = tbl["shell"].as_table()) {
    auto& shell = m_config.shell;
    if (auto v = (*shellTbl)["ui_scale"].value<double>()) {
      shell.uiScale = std::clamp(static_cast<float>(*v), 0.5f, 4.0f);
    }
    if (auto v = (*shellTbl)["font_family"].value<std::string>()) {
      shell.fontFamily = StringUtils::trim(*v);
      if (shell.fontFamily.empty()) {
        shell.fontFamily = "sans-serif";
      }
    }
    if (auto v = (*shellTbl)["lang"].value<std::string>()) {
      shell.lang = *v;
    }
    if (auto v = (*shellTbl)["offline_mode"].value<bool>()) {
      shell.offlineMode = *v;
    }
    if (auto v = (*shellTbl)["telemetry_enabled"].value<bool>()) {
      shell.telemetryEnabled = *v;
    }
    if (auto polkitAgent = (*shellTbl)["polkit_agent"].value<bool>()) {
      shell.polkitAgent = *polkitAgent;
    }
    if (auto v = (*shellTbl)["password_style"].value<std::string>()) {
      if (auto parsed = enumFromKey(kPasswordMaskStyles, *v)) {
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
    if (const auto* shadowTbl = (*shellTbl)["shadow"].as_table()) {
      if (auto v = (*shadowTbl)["blur"].value<int64_t>()) {
        shell.shadow.blur = std::clamp(static_cast<std::int32_t>(*v), 0, 100);
      }
      if (auto v = (*shadowTbl)["offset_x"].value<int64_t>()) {
        shell.shadow.offsetX = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
      }
      if (auto v = (*shadowTbl)["offset_y"].value<int64_t>()) {
        shell.shadow.offsetY = std::clamp(static_cast<std::int32_t>(*v), -40, 40);
      }
      if (auto v = (*shadowTbl)["alpha"].value<double>()) {
        shell.shadow.alpha = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
      }
    }
    if (const auto* panelTbl = (*shellTbl)["panel"].as_table()) {
      if (auto v = (*panelTbl)["background_blur"].value<bool>()) {
        shell.panel.backgroundBlur = *v;
      }
    }
    if (const auto* screenCornersTbl = (*shellTbl)["screen_corners"].as_table()) {
      if (auto v = (*screenCornersTbl)["enabled"].value<bool>()) {
        shell.screenCorners.enabled = *v;
      }
      if (auto v = (*screenCornersTbl)["size"].value<std::int64_t>()) {
        shell.screenCorners.size = std::clamp(static_cast<std::int32_t>(*v), 1, 100);
      }
    }
    if (const auto* mprisTbl = (*shellTbl)["mpris"].as_table()) {
      if (const auto* blacklistNode = mprisTbl->get("blacklist")) {
        shell.mpris.blacklist = readStringArray(*blacklistNode);
      }
    }
    if (auto v = (*shellTbl)["avatar_path"].value<std::string>()) {
      shell.avatarPath = *v;
    }
    if (auto v = (*shellTbl)["settings_show_advanced"].value<bool>()) {
      shell.settingsShowAdvanced = *v;
    }
    if (auto v = (*shellTbl)["show_location"].value<bool>()) {
      shell.showLocation = *v;
    }
    if (auto v = (*shellTbl)["clipboard_auto_paste"].value<std::string>()) {
      if (auto parsed = enumFromKey(kClipboardAutoPasteModes, *v)) {
        shell.clipboardAutoPaste = *parsed;
      }
    }
  }

  // Parse [theme]
  if (auto* themeTbl = tbl["theme"].as_table()) {
    auto& theme = m_config.theme;
    if (auto v = (*themeTbl)["source"].value<std::string>()) {
      if (auto parsed = enumFromKey(kThemeSources, *v)) {
        theme.source = *parsed;
      }
    }
    if (auto builtin = (*themeTbl)["builtin"].value<std::string>()) {
      theme.builtinPalette = *builtin;
    }
    if (auto v = (*themeTbl)["community_palette"].value<std::string>()) {
      theme.communityPalette = *v;
    }
    if (auto v = (*themeTbl)["wallpaper_scheme"].value<std::string>())
      theme.wallpaperScheme = *v;
    if (auto v = (*themeTbl)["mode"].value<std::string>()) {
      if (auto parsed = enumFromKey(kThemeModes, *v)) {
        theme.mode = *parsed;
      }
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
      if (auto mode = enumFromKey(kWallpaperFillModes, *v)) {
        wp.fillMode = *mode;
      }
    }
    if (auto v = (*wpTbl)["fill_color"].value<std::string>()) {
      if (StringUtils::trim(*v).empty()) {
        wp.fillColor = std::nullopt;
      } else {
        wp.fillColor = themeColorFromConfigString(*v);
      }
    }
    if (auto* arr = (*wpTbl)["transition"].as_array()) {
      wp.transitions.clear();
      for (const auto& item : *arr) {
        if (auto s = item.value<std::string>()) {
          if (auto t = enumFromKey(kWallpaperTransitions, *s)) {
            wp.transitions.push_back(*t);
          }
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
      wp.directory = expandUserPathString(*v);
    if (auto v = (*wpTbl)["directory_light"].value<std::string>())
      wp.directoryLight = expandUserPathString(*v);
    if (auto v = (*wpTbl)["directory_dark"].value<std::string>())
      wp.directoryDark = expandUserPathString(*v);
    if (auto* automationTbl = (*wpTbl)["automation"].as_table()) {
      if (auto v = (*automationTbl)["enabled"].value<bool>()) {
        wp.automation.enabled = *v;
      }
      if (auto v = (*automationTbl)["interval_minutes"].value<int64_t>()) {
        wp.automation.intervalMinutes = std::clamp(static_cast<std::int32_t>(*v), 0, 1440);
      }
      if (auto v = (*automationTbl)["order"].value<std::string>()) {
        const std::string order = StringUtils::toLower(StringUtils::trim(*v));
        if (auto parsed = enumFromKey(kWallpaperAutomationOrders, order)) {
          wp.automation.order = *parsed;
        } else {
          kLog.warn("unknown wallpaper automation order \"{}\" (expected: random|alphabetical)", *v);
        }
      }
      if (auto v = (*automationTbl)["recursive"].value<bool>()) {
        wp.automation.recursive = *v;
      }
    }

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
        if (auto v = (*monTbl)["fill_color"].value<std::string>()) {
          if (StringUtils::trim(*v).empty()) {
            ovr.fillColor = std::nullopt;
          } else {
            ovr.fillColor = themeColorFromConfigString(*v);
          }
        }
        if (auto v = (*monTbl)["directory"].value<std::string>())
          ovr.directory = expandUserPathString(*v);
        if (auto v = (*monTbl)["directory_light"].value<std::string>())
          ovr.directoryLight = expandUserPathString(*v);
        if (auto v = (*monTbl)["directory_dark"].value<std::string>())
          ovr.directoryDark = expandUserPathString(*v);
        wp.monitorOverrides.push_back(std::move(ovr));
      }
    }
  }

  // Parse [backdrop]
  if (auto* ovTbl = tbl["backdrop"].as_table()) {
    auto& ov = m_config.backdrop;
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

  auto parseNotificationTable = [this](const toml::table& notifTable) {
    auto& notif = m_config.notification;
    if (auto v = notifTable["enable_daemon"].value<bool>())
      notif.enableDaemon = *v;
    if (auto v = notifTable["position"].value<std::string>())
      notif.position = *v;
    if (auto v = notifTable["layer"].value<std::string>())
      notif.layer = *v;
    if (auto v = notifTable["background_opacity"].value<double>())
      notif.backgroundOpacity = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    if (const auto* v = notifTable.get("monitors")) {
      notif.monitors = readStringArray(*v);
    }
  };

  if (auto* notifTbl = tbl["notification"].as_table()) {
    parseNotificationTable(*notifTbl);
  }
  // Compatibility alias: accept [notifications] as well.
  if (auto* notifTbl = tbl["notifications"].as_table()) {
    parseNotificationTable(*notifTbl);
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
    if (auto v = (*dockTbl)["shadow"].value<bool>())
      dock.shadow = *v;
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
    if (auto v = (*weatherTbl)["effects"].value<bool>())
      weather.effects = *v;
    if (auto v = (*weatherTbl)["address"].value<std::string>())
      weather.address = *v;
    if (auto v = (*weatherTbl)["refresh_minutes"].value<int64_t>())
      weather.refreshMinutes = static_cast<std::int32_t>(*v);
    if (auto v = (*weatherTbl)["unit"].value<std::string>())
      weather.unit = *v;
  }

  // Parse [system]
  if (auto* systemTbl = tbl["system"].as_table()) {
    auto& system = m_config.system;
    if (const auto* monitorTbl = (*systemTbl)["monitor"].as_table()) {
      if (auto v = (*monitorTbl)["enabled"].value<bool>()) {
        system.monitor.enabled = *v;
      }
    }
  }

  // Parse [audio]
  if (auto* audioTbl = tbl["audio"].as_table()) {
    auto& audio = m_config.audio;
    if (auto v = (*audioTbl)["enable_overdrive"].value<bool>()) {
      audio.enableOverdrive = *v;
    }
    if (auto v = (*audioTbl)["enable_sounds"].value<bool>()) {
      audio.enableSounds = *v;
    }
    if (auto v = (*audioTbl)["sound_volume"].value<double>()) {
      audio.soundVolume = std::clamp(static_cast<float>(*v), 0.0f, 1.0f);
    }
    if (auto v = (*audioTbl)["volume_change_sound"].value<std::string>()) {
      audio.volumeChangeSound = *v;
    }
    if (auto v = (*audioTbl)["notification_sound"].value<std::string>()) {
      audio.notificationSound = *v;
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
          if (const auto parsed = enumFromKey(kBrightnessBackendPreferences, StringUtils::trim(*v));
              parsed.has_value()) {
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

  // Parse [[control_center.shortcuts]]
  if (auto* ccTbl = tbl["control_center"].as_table()) {
    if (auto* shortcutsArr = (*ccTbl)["shortcuts"].as_array()) {
      m_config.controlCenter.shortcuts.clear();
      for (const auto& entry : *shortcutsArr) {
        auto* entryTbl = entry.as_table();
        if (entryTbl == nullptr) {
          continue;
        }
        ShortcutConfig sc;
        if (auto v = (*entryTbl)["type"].value<std::string>()) {
          sc.type = *v;
        }
        if (auto v = (*entryTbl)["label"].value<std::string>()) {
          sc.label = *v;
        }
        if (auto v = (*entryTbl)["icon"].value<std::string>()) {
          sc.icon = *v;
        }
        if (!sc.type.empty()) {
          m_config.controlCenter.shortcuts.push_back(std::move(sc));
        }
      }
    }
  }
  if (m_config.controlCenter.shortcuts.empty()) {
    m_config.controlCenter.shortcuts = {
        {"wifi", {}, {}},       {"bluetooth", {}, {}},    {"wallpaper", {}, {}},     {"idle_inhibitor", {}, {}},
        {"nightlight", {}, {}}, {"notification", {}, {}}, {"power_profile", {}, {}}, {"session", {}, {}},
    };
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

  std::string barOrder;
  for (const auto& bar : m_config.bars) {
    if (!barOrder.empty()) {
      barOrder += ", ";
    }
    barOrder += bar.name;
  }
  kLog.info("{} bar(s) defined", m_config.bars.size());
  kLog.info("bar order: {}", barOrder);
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

void ConfigService::registerIpc(IpcService& ipc) {
  ipc.registerHandler(
      "config-reload",
      [this](const std::string&) -> std::string {
        forceReload();
        return "ok\n";
      },
      "config-reload", "Reload the config file");
}
