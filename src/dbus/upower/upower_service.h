#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>

class SystemBus;

namespace sdbus {
  class IProxy;
  class ObjectPath;
} // namespace sdbus

enum class BatteryState : std::uint8_t {
  Unknown = 0,
  Charging = 1,
  Discharging = 2,
  Empty = 3,
  FullyCharged = 4,
  PendingCharge = 5,
  PendingDischarge = 6,
};

[[nodiscard]] std::string batteryStateLabel(BatteryState state);

struct UPowerState {
  double percentage = 0.0;
  BatteryState state = BatteryState::Unknown;
  std::int64_t timeToEmpty = 0; // seconds
  std::int64_t timeToFull = 0;  // seconds
  bool isPresent = false;
  bool onBattery = false;

  bool operator==(const UPowerState&) const = default;
};

class UPowerService {
public:
  using ChangeCallback = std::function<void()>;

  explicit UPowerService(SystemBus& bus);

  void setChangeCallback(ChangeCallback callback);
  void refresh();

  [[nodiscard]] const UPowerState& state() const noexcept { return m_state; }

private:
  [[nodiscard]] UPowerState readState() const;
  void emitChangedIfNeeded(const UPowerState& next);
  void bindBatteryDevice(const sdbus::ObjectPath& path);
  void scanDevices();

  SystemBus& m_bus;
  std::unique_ptr<sdbus::IProxy> m_upowerProxy;
  std::unique_ptr<sdbus::IProxy> m_deviceProxy;
  UPowerState m_state;
  ChangeCallback m_changeCallback;
};
