#pragma once

#include "config/config_service.h"

#include <functional>
#include <memory>
#include <string>
#include <vector>

class WaylandConnection;
struct ext_idle_notification_v1;
struct ext_idle_notifier_v1;

class IdleManager {
public:
  using CommandRunner = std::function<bool(const std::string&)>;

  IdleManager();
  ~IdleManager();

  IdleManager(const IdleManager&) = delete;
  IdleManager& operator=(const IdleManager&) = delete;

  bool initialize(WaylandConnection& wayland);
  void setCommandRunner(CommandRunner runner);
  void reload(const IdleConfig& config);
  static void handleIdled(void* data, ext_idle_notification_v1* notification);
  static void handleResumed(void* data, ext_idle_notification_v1* notification);

private:
  struct BehaviorState {
    IdleManager* owner = nullptr;
    IdleBehaviorConfig config;
    ext_idle_notification_v1* notification = nullptr;
    bool idled = false;
  };

  void clearBehaviors();
  void createBehavior(const IdleBehaviorConfig& config);
  void runBehavior(BehaviorState& behavior);
  void runResumeBehavior(BehaviorState& behavior);
  bool runCommand(const std::string& command) const;

  WaylandConnection* m_wayland = nullptr;
  ext_idle_notifier_v1* m_notifier = nullptr;
  CommandRunner m_commandRunner;
  std::vector<std::unique_ptr<BehaviorState>> m_behaviors;
};
