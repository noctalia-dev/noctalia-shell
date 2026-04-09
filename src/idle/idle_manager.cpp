#include "idle/idle_manager.h"

#include "core/log.h"
#include "wayland/wayland_connection.h"

#include "ext-idle-notify-v1-client-protocol.h"

namespace {

  constexpr Logger kLog("idle");

  const ext_idle_notification_v1_listener kIdleNotificationListener = {
      .idled = &IdleManager::handleIdled,
      .resumed = &IdleManager::handleResumed,
  };

} // namespace

IdleManager::IdleManager() = default;

IdleManager::~IdleManager() { clearBehaviors(); }

bool IdleManager::initialize(WaylandConnection& wayland) {
  m_wayland = &wayland;
  m_notifier = m_wayland->idleNotifier();
  if (m_notifier == nullptr) {
    kLog.info("idle notify protocol unavailable");
  }
  return true;
}

void IdleManager::setCommandRunner(CommandRunner runner) { m_commandRunner = std::move(runner); }

void IdleManager::reload(const IdleConfig& config) {
  clearBehaviors();

  if (m_notifier == nullptr) {
    return;
  }
  if (m_wayland == nullptr || m_wayland->seat() == nullptr) {
    kLog.warn("cannot register idle behaviors without a Wayland seat");
    return;
  }

  for (const auto& behavior : config.behaviors) {
    createBehavior(behavior);
  }
}

void IdleManager::clearBehaviors() {
  for (auto& behavior : m_behaviors) {
    if (behavior->notification != nullptr) {
      ext_idle_notification_v1_destroy(behavior->notification);
      behavior->notification = nullptr;
    }
  }
  m_behaviors.clear();
}

void IdleManager::createBehavior(const IdleBehaviorConfig& config) {
  if (!config.enabled) {
    return;
  }
  if (config.timeoutSeconds < 0) {
    kLog.warn("idle behavior '{}' ignored: timeout must be >= 0 seconds", config.name);
    return;
  }
  if (config.command.empty()) {
    kLog.warn("idle behavior '{}' ignored: needs a command", config.name);
    return;
  }

  auto behavior = std::make_unique<BehaviorState>();
  behavior->owner = this;
  behavior->config = config;
  const auto timeoutMs = static_cast<std::uint32_t>(config.timeoutSeconds) * 1000u;
  behavior->notification = ext_idle_notifier_v1_get_idle_notification(m_notifier, timeoutMs, m_wayland->seat());
  if (behavior->notification == nullptr) {
    kLog.warn("failed to register idle behavior '{}'", config.name);
    return;
  }

  ext_idle_notification_v1_add_listener(behavior->notification, &kIdleNotificationListener, behavior.get());
  kLog.info("registered idle behavior '{}' timeout={}s", config.name, config.timeoutSeconds);
  m_behaviors.push_back(std::move(behavior));
}

void IdleManager::runBehavior(BehaviorState& behavior) {
  const auto& config = behavior.config;
  if (!runCommand(config.command)) {
    kLog.warn("idle behavior '{}' command failed", config.name);
  }
}

bool IdleManager::runCommand(const std::string& command) const {
  if (command.empty()) {
    return true;
  }
  if (!m_commandRunner) {
    return false;
  }
  return m_commandRunner(command);
}

void IdleManager::handleIdled(void* data, ext_idle_notification_v1* /*notification*/) {
  auto* behavior = static_cast<BehaviorState*>(data);
  if (behavior == nullptr || behavior->owner == nullptr || behavior->idled) {
    return;
  }

  behavior->idled = true;
  kLog.info("idle behavior '{}' triggered", behavior->config.name);
  behavior->owner->runBehavior(*behavior);
}

void IdleManager::handleResumed(void* data, ext_idle_notification_v1* /*notification*/) {
  auto* behavior = static_cast<BehaviorState*>(data);
  if (behavior == nullptr || !behavior->idled) {
    return;
  }

  behavior->idled = false;
  kLog.info("idle behavior '{}' resumed", behavior->config.name);
}
