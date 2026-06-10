#include "shell/session/session_action_runner.h"

#include "compositors/compositor_detect.h"
#include "compositors/compositor_platform.h"
#include "core/log.h"
#include "core/process.h"
#include "i18n/i18n.h"
#include "notification/notifications.h"
#include "shell/lockscreen/lock_screen.h"
#include "util/string_utils.h"

#include <chrono>
#include <cstdlib>
#include <initializer_list>
#include <string>
#include <string_view>
#include <thread>
#include <utility>

namespace {

  constexpr Logger kLog("session");
  constexpr std::chrono::milliseconds kPowerCommandTimeout{5000};

  [[nodiscard]] const char* valueOrUnset(const char* value) {
    return value != nullptr && value[0] != '\0' ? value : "<unset>";
  }

  void logActionContext(std::string_view action) {
    const compositors::CompositorKind compositor = compositors::detect();
    kLog.info(
        "{} requested: compositor={} env_hint=\"{}\" xdg_session_id={} user={}", action, compositors::name(compositor),
        compositors::envHint(), valueOrUnset(std::getenv("XDG_SESSION_ID")), valueOrUnset(std::getenv("USER"))
    );
  }

  [[nodiscard]] std::string commandLabel(std::initializer_list<const char*> args) {
    std::string label;
    for (const char* arg : args) {
      if (arg == nullptr) {
        continue;
      }
      if (!label.empty()) {
        label += ' ';
      }
      label += arg;
    }
    return label.empty() ? "<empty>" : label;
  }

  void
  logSessionCommandFailure(std::string_view action, std::string_view commandLabel, const process::RunResult& result) {
    if (result.timedOut) {
      kLog.warn("{}: {} timed out after {}ms", action, commandLabel, kPowerCommandTimeout.count());
    } else if (!result.err.empty()) {
      kLog.warn("{}: {} failed with code {}: {}", action, commandLabel, result.exitCode, result.err);
    } else if (!result.out.empty()) {
      kLog.warn("{}: {} failed with code {}: {}", action, commandLabel, result.exitCode, result.out);
    } else {
      kLog.warn("{}: {} failed with code {}", action, commandLabel, result.exitCode);
    }
  }

  [[nodiscard]] bool runCheckedSessionCommand(
      std::string_view action, std::initializer_list<std::initializer_list<const char*>> commands
  ) {
    bool attempted = false;
    for (const auto& command : commands) {
      if (command.size() == 0) {
        continue;
      }
      const char* executable = *command.begin();
      if (executable == nullptr || executable[0] == '\0') {
        continue;
      }
      if (!process::commandExists(executable)) {
        kLog.debug("{}: {} not found", action, executable);
        continue;
      }

      attempted = true;
      const std::string label = commandLabel(command);
      const process::RunResult result = process::runSyncWithTimeout(command, kPowerCommandTimeout);
      if (result) {
        kLog.info("{}: {} accepted", action, label);
        return true;
      }
      logSessionCommandFailure(action, label, result);
    }

    if (!attempted) {
      kLog.warn("{}: no supported command found", action);
    } else {
      kLog.warn("{}: all command methods failed", action);
    }
    return false;
  }

  [[nodiscard]] bool runSuspendBlocking() {
    logActionContext("suspend");
    return runCheckedSessionCommand(
        "suspend",
        {
            {"systemctl", "suspend"},
            {"loginctl", "suspend"},
        }
    );
  }

  [[nodiscard]] bool launchSuspendDetached() {
    logActionContext("suspend");
    return process::launchFirstAvailable({{"systemctl", "suspend"}, {"loginctl", "suspend"}});
  }

  [[nodiscard]] bool doReboot() {
    logActionContext("reboot");
    return runCheckedSessionCommand(
        "reboot",
        {
            {"systemctl", "reboot"},
            {"loginctl", "reboot"},
            {"reboot"},
            {"/sbin/reboot"},
            {"/usr/sbin/reboot"},
        }
    );
  }

  [[nodiscard]] bool doShutdown() {
    logActionContext("shutdown");
    return runCheckedSessionCommand(
        "shutdown",
        {
            {"systemctl", "poweroff"},
            {"loginctl", "poweroff"},
            {"poweroff"},
            {"/sbin/poweroff"},
            {"/usr/sbin/poweroff"},
        }
    );
  }

  [[nodiscard]] bool requestLock(LockScreen& lockScreen) {
    logActionContext("lock");
    if (!lockScreen.lock()) {
      kLog.warn("lock: lock screen request failed");
      return false;
    }
    kLog.info("lock: lock screen requested");
    return true;
  }

  void runPowerAction(std::function<bool()> hook, std::function<bool()> action, std::string_view actionName) {
    std::thread([hook = std::move(hook), action = std::move(action), actionName = std::string(actionName)]() mutable {
      if (hook && !hook()) {
        kLog.warn("{} cancelled because a configured hook failed", actionName);
        return;
      }
      if (!action()) {
        kLog.warn("{} failed after hooks completed", actionName);
      }
    }).detach();
  }

  void runShellCommand(std::function<bool()> hook, std::string command, std::string_view actionName) {
    std::thread([hook = std::move(hook), command = std::move(command), actionName = std::string(actionName)]() mutable {
      if (hook && !hook()) {
        kLog.warn("{} cancelled because a configured hook failed", actionName);
        return;
      }
      if (!process::runAsync(command)) {
        kLog.warn("{}: command failed", actionName);
      }
    }).detach();
  }

} // namespace

SessionActionRunner::SessionActionRunner(CompositorPlatform& platform, LockScreen& lockScreen, SessionActionHooks hooks)
    : m_platform(platform), m_lockScreen(lockScreen), m_hooks(std::move(hooks)) {}

void SessionActionRunner::setHooks(SessionActionHooks hooks) { m_hooks = std::move(hooks); }

void SessionActionRunner::invoke(const SessionPanelActionConfig& cfg) const {
  if (cfg.command.has_value() && !StringUtils::trim(*cfg.command).empty()) {
    runShellCommand(hookFor(cfg.action), StringUtils::trim(*cfg.command), cfg.action);
    return;
  }

  if (cfg.action == "command") {
    kLog.warn("session panel: custom action missing command");
    return;
  }

  if (cfg.action == "logout") {
    runPowerAction(m_hooks.onLogout, [platform = &m_platform]() { return platform->requestSessionExit(); }, "logout");
    return;
  }
  if (cfg.action == "suspend") {
    runPowerAction({}, [this]() { return suspendBlocking(); }, "suspend");
    return;
  }
  if (cfg.action == "lock_and_suspend") {
    if (!lockThenSuspendDetached()) {
      notify::error("Noctalia", i18n::tr("session.errors.lock-title"), i18n::tr("session.errors.lock-body"));
    }
    return;
  }
  if (cfg.action == "reboot") {
    runPowerAction(m_hooks.onReboot, []() { return doReboot(); }, "reboot");
    return;
  }
  if (cfg.action == "shutdown") {
    runPowerAction(m_hooks.onShutdown, []() { return doShutdown(); }, "shutdown");
    return;
  }
  if (cfg.action == "lock") {
    if (!lock()) {
      notify::error("Noctalia", i18n::tr("session.errors.lock-title"), i18n::tr("session.errors.lock-body"));
    }
    return;
  }
}

std::function<bool()> SessionActionRunner::hookFor(std::string_view action) const {
  if (action == "logout") {
    return m_hooks.onLogout;
  }
  if (action == "reboot") {
    return m_hooks.onReboot;
  }
  if (action == "shutdown") {
    return m_hooks.onShutdown;
  }
  return {};
}

bool SessionActionRunner::lock() const { return requestLock(m_lockScreen); }

bool SessionActionRunner::requestSuspendDetached() const { return launchSuspendDetached(); }

bool SessionActionRunner::lockThenSuspendDetached() const {
  m_lockScreen.runAfterSessionLocked([this]() { (void)requestSuspendDetached(); });
  return true;
}

bool SessionActionRunner::suspendBlocking() const { return runSuspendBlocking(); }
