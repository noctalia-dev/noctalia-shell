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

  explicit LogindService(SystemBus& bus);

  void setPrepareForSleepCallback(PrepareForSleepCallback callback);

private:
  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_managerProxy;
  PrepareForSleepCallback m_prepareForSleepCallback;
};
