#pragma once

#include "config/config_types.h"

#include <string>
#include <string_view>
#include <unordered_map>

class NotificationManager;
class UPowerService;
struct UPowerDeviceInfo;

[[nodiscard]] int batteryWarningThresholdForDevice(
    const BatteryConfig& config, const UPowerDeviceInfo& device, const UPowerDeviceInfo* systemBattery = nullptr
);
[[nodiscard]] int
batteryWarningThresholdForSelector(const BatteryConfig& config, const UPowerService* upower, std::string_view selector);

class BatteryWarningMonitor {
public:
  void reset(const BatteryConfig& config, const UPowerService& upower);
  void update(const BatteryConfig& config, const UPowerService& upower, NotificationManager& notifications);

private:
  struct DeviceWarningState {
    bool initialized = false;
    bool warningActive = false;
    int threshold = -1;
  };

  std::unordered_map<std::string, DeviceWarningState> m_devices;
};
