#pragma once

#include <functional>
#include <memory>

class SystemBus;

namespace sdbus {
  class IProxy;
}

class LogindService {
public:
  using PrepareForSleepCallback = std::function<void(bool sleeping)>;
  using SessionLockCallback = std::function<void()>;

  explicit LogindService(SystemBus& bus);

  void setPrepareForSleepCallback(PrepareForSleepCallback callback);
  void setLockCallback(SessionLockCallback callback);
  void setUnlockCallback(SessionLockCallback callback);

  void syncSessionLocked();
  void syncSessionUnlocked();

private:
  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_managerProxy;
  std::unique_ptr<sdbus::IProxy> m_sessionProxy;
  PrepareForSleepCallback m_prepareForSleepCallback;
  SessionLockCallback m_lockCallback;
  SessionLockCallback m_unlockCallback;
};
