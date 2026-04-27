#include "hooks/hook_manager.h"

#include "core/log.h"

#include <cstdlib>

namespace {

  constexpr Logger kLog("hooks");

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
  const std::string_view name = hookKindKey(kind);
  kLog.debug("hook '{}' running {} command(s)", name, cmds.size());
  for (const auto& cmd : cmds) {
    if (!m_runner(cmd)) {
      kLog.warn("hook '{}' command failed: {}", name, cmd);
    }
  }
}

void HookManager::fire(HookKind kind, std::initializer_list<EnvVar> env) const {
  for (const auto& [key, value] : env) {
    ::setenv(key, value.c_str(), 1);
  }
  fire(kind);
  for (const auto& [key, value] : env) {
    ::unsetenv(key);
  }
}
