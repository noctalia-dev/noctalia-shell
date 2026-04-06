#include "dbus/upower/upower_service.h"

#include "core/log.h"
#include "dbus/system_bus.h"

#include <map>
#include <sdbus-c++/IProxy.h>
#include <sdbus-c++/Types.h>
#include <string_view>
#include <vector>

namespace {

static const sdbus::ServiceName k_upowerBusName{"org.freedesktop.UPower"};
static const sdbus::ObjectPath k_upowerObjectPath{"/org/freedesktop/UPower"};
static constexpr auto k_upowerInterface = "org.freedesktop.UPower";
static constexpr auto k_deviceInterface = "org.freedesktop.UPower.Device";
static constexpr auto k_propertiesInterface = "org.freedesktop.DBus.Properties";

// UPower device types
constexpr std::uint32_t k_deviceTypeBattery = 2;

// UPower battery states
constexpr std::uint32_t k_stateCharging = 1;
constexpr std::uint32_t k_stateDischarging = 2;
constexpr std::uint32_t k_stateEmpty = 3;
constexpr std::uint32_t k_stateFullyCharged = 4;
constexpr std::uint32_t k_statePendingCharge = 5;
constexpr std::uint32_t k_statePendingDischarge = 6;

template <typename T>
T getPropertyOr(sdbus::IProxy& proxy, std::string_view iface, std::string_view propertyName, T fallback) {
  try {
    const sdbus::Variant value = proxy.getProperty(propertyName).onInterface(iface);
    return value.get<T>();
  } catch (const sdbus::Error&) {
    return fallback;
  }
}

BatteryState decodeBatteryState(std::uint32_t raw) {
  switch (raw) {
  case k_stateCharging:
    return BatteryState::Charging;
  case k_stateDischarging:
    return BatteryState::Discharging;
  case k_stateEmpty:
    return BatteryState::Empty;
  case k_stateFullyCharged:
    return BatteryState::FullyCharged;
  case k_statePendingCharge:
    return BatteryState::PendingCharge;
  case k_statePendingDischarge:
    return BatteryState::PendingDischarge;
  default:
    return BatteryState::Unknown;
  }
}

} // namespace

UPowerService::UPowerService(SystemBus& bus) : m_bus(bus) {
  m_upowerProxy = sdbus::createProxy(m_bus.connection(), k_upowerBusName, k_upowerObjectPath);

  // Listen for devices being added/removed so we can rebind the battery proxy
  m_upowerProxy->uponSignal("DeviceAdded").onInterface(k_upowerInterface).call([this](const sdbus::ObjectPath&) {
    scanDevices();
    refresh();
  });

  m_upowerProxy->uponSignal("DeviceRemoved").onInterface(k_upowerInterface).call([this](const sdbus::ObjectPath& path) {
    if (m_deviceProxy != nullptr) {
      // If our tracked device was removed, clear it and re-scan
      try {
        if (m_deviceProxy->getObjectPath() == path) {
          m_deviceProxy.reset();
          scanDevices();
        }
      } catch (const sdbus::Error&) {
        m_deviceProxy.reset();
        scanDevices();
      }
    }
    refresh();
  });

  scanDevices();
  refresh();

  logDebug("upower: service initialized");
}

void UPowerService::setChangeCallback(ChangeCallback callback) { m_changeCallback = std::move(callback); }

void UPowerService::refresh() { emitChangedIfNeeded(readState()); }

void UPowerService::scanDevices() {
  if (m_deviceProxy != nullptr) {
    return; // already have a battery bound
  }

  std::vector<sdbus::ObjectPath> paths;
  try {
    m_upowerProxy->callMethod("EnumerateDevices").onInterface(k_upowerInterface).storeResultsTo(paths);
  } catch (const sdbus::Error& e) {
    logWarn("upower: EnumerateDevices failed: {}", e.what());
    return;
  }

  for (const auto& path : paths) {
    try {
      auto probe = sdbus::createProxy(m_bus.connection(), k_upowerBusName, path);
      const auto type = getPropertyOr<std::uint32_t>(*probe, k_deviceInterface, "Type", 0);
      const auto present = getPropertyOr<bool>(*probe, k_deviceInterface, "IsPresent", false);
      if (type == k_deviceTypeBattery && present) {
        bindBatteryDevice(path);
        return;
      }
    } catch (const sdbus::Error&) {
      continue;
    }
  }
}

void UPowerService::bindBatteryDevice(const sdbus::ObjectPath& path) {
  m_deviceProxy = sdbus::createProxy(m_bus.connection(), k_upowerBusName, path);

  m_deviceProxy->uponSignal("PropertiesChanged")
      .onInterface(k_propertiesInterface)
      .call([this](const std::string& interfaceName, const std::map<std::string, sdbus::Variant>& /*changed*/,
                   const std::vector<std::string>& /*invalidated*/) {
        if (interfaceName == k_deviceInterface) {
          refresh();
        }
      });

  logDebug("upower: bound battery device {}", std::string(path));
}

UPowerState UPowerService::readState() const {
  UPowerState next;

  next.onBattery = getPropertyOr<bool>(*m_upowerProxy, k_upowerInterface, "OnBattery", false);

  if (m_deviceProxy == nullptr) {
    return next;
  }

  next.percentage = getPropertyOr<double>(*m_deviceProxy, k_deviceInterface, "Percentage", 0.0);
  next.isPresent = getPropertyOr<bool>(*m_deviceProxy, k_deviceInterface, "IsPresent", false);
  const auto rawState = getPropertyOr<std::uint32_t>(*m_deviceProxy, k_deviceInterface, "State", 0);
  next.state = decodeBatteryState(rawState);
  next.timeToEmpty = getPropertyOr<std::int64_t>(*m_deviceProxy, k_deviceInterface, "TimeToEmpty", 0);
  next.timeToFull = getPropertyOr<std::int64_t>(*m_deviceProxy, k_deviceInterface, "TimeToFull", 0);

  return next;
}

void UPowerService::emitChangedIfNeeded(const UPowerState& next) {
  if (next == m_state) {
    return;
  }

  m_state = next;
  if (m_changeCallback) {
    m_changeCallback();
  }
}
