#pragma once

#include "config/config_service.h"

#include <functional>
#include <initializer_list>
#include <string>
#include <utility>

class HookManager {
public:
  using CommandRunner = std::function<bool(const std::string& command)>;
  using EnvVar = std::pair<const char*, std::string>;

  void setCommandRunner(CommandRunner runner);
  void reload(const HooksConfig& config);
  void fire(HookKind kind) const;
  void fire(HookKind kind, std::initializer_list<EnvVar> env) const;

  [[nodiscard]] const HooksConfig& config() const noexcept { return m_config; }

private:
  HooksConfig m_config;
  CommandRunner m_runner;
};
