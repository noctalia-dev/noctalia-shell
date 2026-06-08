#pragma once

#include "config/config_types.h"
#include "dbus/upower/upower_service.h"
#include "hooks/hook_manager.h"

#include <optional>
#include <vector>

class BatteryHookState {
public:
  struct Event {
    HookKind kind = HookKind::Count;
    std::vector<HookManager::EnvVar> env;
  };

  void reset(const UPowerState& state);
  [[nodiscard]] std::vector<Event> update(const UPowerState& state);

private:
  bool m_initialized = false;
  std::optional<HookKind> m_lastStateHook;
  std::optional<int> m_lastPercent;
};
