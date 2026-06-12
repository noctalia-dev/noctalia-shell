#include "shell/session/session_ipc.h"

#include "config/config_service.h"
#include "config/config_types.h"
#include "ipc/ipc_arg_parse.h"
#include "ipc/ipc_service.h"
#include "shell/lockscreen/lock_screen.h"
#include "shell/session/session_action_runner.h"

#include <string>
#include <string_view>

namespace {

  [[nodiscard]] SessionPanelActionConfig sessionActionConfig(std::string_view action) {
    SessionPanelActionConfig cfg;
    cfg.action = std::string(action);
    return cfg;
  }

  [[nodiscard]] std::string unknownSessionActionError(std::string_view action) {
    return "error: unknown session action \""
        + std::string(action)
        + "\" (try: lock, suspend, lock-and-suspend, logout, reboot, shutdown)\n";
  }

} // namespace

void registerSessionIpc(IpcService& ipc, SessionActionRunner& runner, LockScreen& lockScreen, ConfigService& config) {
  const auto dispatch = [&runner, &lockScreen, &config](const std::string& args) -> std::string {
    const auto parts = noctalia::ipc::splitWords(args);
    if (parts.empty()) {
      return "error: session requires <lock|suspend|lock-and-suspend|logout|reboot|shutdown>\n";
    }

    const std::string& action = parts[0];
    if (action == "lock") {
      if (!config.isLockScreenEnabled()) {
        return "error: lock screen disabled\n";
      }
      if (lockScreen.lock()) {
        return "ok\n";
      }
      return "error: lock screen unavailable\n";
    }
    if (action == "suspend") {
      if (runner.requestSuspendDetached()) {
        return "ok\n";
      }
      return "error: failed to suspend\n";
    }
    if (action == "lock-and-suspend") {
      if (!config.isLockScreenEnabled()) {
        if (runner.requestSuspendDetached()) {
          return "ok\n";
        }
        return "error: failed to suspend\n";
      }
      if (runner.lockThenSuspendDetached()) {
        return "ok\n";
      }
      return "error: failed to lock and suspend\n";
    }
    if (action == "logout" || action == "reboot" || action == "shutdown") {
      runner.invoke(sessionActionConfig(action));
      return "ok\n";
    }

    return unknownSessionActionError(action);
  };

  ipc.registerHandler(
      "session", dispatch, "session <lock|suspend|lock-and-suspend|logout|reboot|shutdown>",
      "Run a built-in session action"
  );
}
