#include "hooks/hook_manager.h"

#include "core/log.h"

namespace {

  constexpr Logger kLog("hooks");

  const char* hookKindName(HookKind kind) {
    switch (kind) {
    case HookKind::Started:
      return "started";
    case HookKind::WallpaperChanged:
      return "wallpaper_changed";
    case HookKind::ColorsChanged:
      return "colors_changed";
    case HookKind::SessionLocked:
      return "session_locked";
    case HookKind::SessionUnlocked:
      return "session_unlocked";
    case HookKind::LoggingOut:
      return "logging_out";
    case HookKind::Rebooting:
      return "rebooting";
    case HookKind::ShuttingDown:
      return "shutting_down";
    case HookKind::WifiEnabled:
      return "wifi_enabled";
    case HookKind::WifiDisabled:
      return "wifi_disabled";
    case HookKind::BluetoothEnabled:
      return "bluetooth_enabled";
    case HookKind::BluetoothDisabled:
      return "bluetooth_disabled";
    case HookKind::BatteryStateChanged:
      return "battery_state_changed";
    case HookKind::BatteryUnderThreshold:
      return "battery_under_threshold";
    case HookKind::Count:
      break;
    }
    return "unknown";
  }

} // namespace

void HookManager::setCommandRunner(CommandRunner runner) { m_runner = std::move(runner); }

void HookManager::reload(const HooksConfig& config) { m_config = config; }

void HookManager::fire(HookKind kind) const {
  if (kind == HookKind::Count || !m_runner) {
    return;
  }
  const auto& cmds = m_config.commands[static_cast<std::size_t>(kind)];
  if (cmds.empty()) {
    return;
  }
  kLog.debug("hook '{}' running {} command(s)", hookKindName(kind), cmds.size());
  for (const auto& cmd : cmds) {
    if (!m_runner(cmd)) {
      kLog.warn("hook '{}' command failed: {}", hookKindName(kind), cmd);
    }
  }
}
