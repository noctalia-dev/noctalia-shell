#pragma once

#include "config/config_types.h"

#include <functional>
#include <string_view>

class CompositorPlatform;
class LockScreen;

struct SessionActionHooks {
  std::function<bool()> onLogout;
  std::function<bool()> onReboot;
  std::function<bool()> onShutdown;
};

class SessionActionRunner {
public:
  explicit SessionActionRunner(CompositorPlatform& platform, LockScreen& lockScreen, SessionActionHooks hooks = {});

  void setHooks(SessionActionHooks hooks);
  void invoke(const SessionPanelActionConfig& cfg) const;
  [[nodiscard]] bool lock() const;
  [[nodiscard]] bool requestSuspendDetached() const;
  [[nodiscard]] bool lockThenSuspendDetached() const;

private:
  [[nodiscard]] std::function<bool()> hookFor(std::string_view action) const;
  [[nodiscard]] bool suspendBlocking() const;

  CompositorPlatform& m_platform;
  LockScreen& m_lockScreen;
  SessionActionHooks m_hooks;
};
