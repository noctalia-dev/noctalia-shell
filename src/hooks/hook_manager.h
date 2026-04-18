#pragma once

#include "config/config_service.h"

#include <functional>
#include <string>

class HookManager {
public:
  using CommandRunner = std::function<bool(const std::string& command)>;

  void setCommandRunner(CommandRunner runner);
  void reload(const HooksConfig& config);
  void fire(HookKind kind) const;

  [[nodiscard]] const HooksConfig& config() const noexcept { return m_config; }

private:
  HooksConfig m_config;
  CommandRunner m_runner;
};
