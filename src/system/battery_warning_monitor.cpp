#include "system/battery_warning_monitor.h"

#include "dbus/upower/upower_service.h"
#include "i18n/i18n.h"
#include "notification/notification_manager.h"
#include "util/string_utils.h"

#include <algorithm>
#include <cmath>
#include <string>
#include <unordered_set>

namespace {

  bool isAutoSelector(std::string_view selector) {
    const std::string normalized = StringUtils::toLower(StringUtils::trim(selector));
    return normalized.empty() || normalized == "auto";
  }

  bool isPluggedIn(BatteryState state) {
    return state == BatteryState::Charging
        || state == BatteryState::FullyCharged
        || state == BatteryState::PendingCharge;
  }

  bool isWarningState(const UPowerDeviceInfo& device, int threshold) {
    return threshold > 0
        && device.state.isPresent
        && static_cast<int>(std::round(device.state.percentage)) <= threshold
        && !isPluggedIn(device.state.state);
  }

  std::string deviceKey(const UPowerDeviceInfo& device) {
    if (!device.path.empty()) {
      return device.path;
    }
    if (!device.nativePath.empty()) {
      return device.nativePath;
    }
    if (!device.serial.empty()) {
      return device.serial;
    }
    return device.model;
  }

  std::string deviceLabel(const UPowerDeviceInfo& device) {
    if (device.isLaptopBattery()) {
      return i18n::tr("notifications.internal.battery");
    }

    const std::string nativeName =
        !device.nativePath.empty() ? StringUtils::pathTail(device.nativePath) : StringUtils::pathTail(device.path);
    if (!device.vendor.empty() && !device.model.empty()) {
      return device.vendor + " " + device.model;
    }
    if (!device.model.empty()) {
      return device.model;
    }
    if (!device.vendor.empty()) {
      return device.vendor;
    }
    if (!nativeName.empty()) {
      return nativeName;
    }
    return i18n::tr("notifications.internal.battery-device");
  }

  bool isSystemBattery(const UPowerDeviceInfo& device, const UPowerDeviceInfo* systemBattery) {
    return systemBattery != nullptr && !device.path.empty() && device.path == systemBattery->path;
  }

} // namespace

int batteryWarningThresholdForDevice(
    const BatteryConfig& config, const UPowerDeviceInfo& device, const UPowerDeviceInfo* systemBattery
) {
  if (!isSystemBattery(device, systemBattery)) {
    for (const auto& deviceThreshold : config.deviceThresholds) {
      if (upowerDeviceMatchesSelector(device, deviceThreshold.selector)) {
        return deviceThreshold.warningThreshold;
      }
    }
  }
  return device.isLaptopBattery() ? config.warningThreshold : 0;
}

int batteryWarningThresholdForSelector(
    const BatteryConfig& config, const UPowerService* upower, std::string_view selector
) {
  if (upower != nullptr) {
    const auto* systemBattery = upower->defaultSystemBattery();
    if (isAutoSelector(selector)) {
      if (systemBattery != nullptr) {
        return batteryWarningThresholdForDevice(config, *systemBattery, systemBattery);
      }
    } else if (const auto* device = upower->deviceForSelector(selector); device != nullptr) {
      return batteryWarningThresholdForDevice(config, *device, systemBattery);
    }
  }
  return config.warningThreshold;
}

void BatteryWarningMonitor::reset(const BatteryConfig& config, const UPowerService& upower) {
  m_devices.clear();
  const auto* systemBattery = upower.defaultSystemBattery();
  for (const auto& device : upower.batteryDevices()) {
    const std::string key = deviceKey(device);
    if (key.empty()) {
      continue;
    }
    const int threshold = batteryWarningThresholdForDevice(config, device, systemBattery);
    m_devices.emplace(
        key,
        DeviceWarningState{
            .initialized = true,
            .warningActive = isWarningState(device, threshold),
            .threshold = threshold,
        }
    );
  }
}

void BatteryWarningMonitor::update(
    const BatteryConfig& config, const UPowerService& upower, NotificationManager& notifications
) {
  std::unordered_set<std::string> seen;
  const auto* systemBattery = upower.defaultSystemBattery();
  for (const auto& device : upower.batteryDevices()) {
    const std::string key = deviceKey(device);
    if (key.empty()) {
      continue;
    }
    seen.insert(key);

    const int threshold = batteryWarningThresholdForDevice(config, device, systemBattery);
    const bool warning = isWarningState(device, threshold);
    auto& state = m_devices[key];
    if (!state.initialized || state.threshold != threshold) {
      state.initialized = true;
      state.warningActive = warning;
      state.threshold = threshold;
      continue;
    }

    if (!warning) {
      state.warningActive = false;
      continue;
    }

    if (state.warningActive) {
      continue;
    }

    state.warningActive = true;
    const int percent = std::clamp(static_cast<int>(std::round(device.state.percentage)), 0, 100);
    const std::string label = deviceLabel(device);
    notifications.addInternal(
        i18n::tr("notifications.internal.battery"), i18n::tr("notifications.internal.battery-low-title"),
        i18n::tr("notifications.internal.battery-low-body", "device", label, "percent", percent), Urgency::Critical,
        kDefaultNotificationTimeout * 2, std::string("noctalia-glyph:battery-exclamation")
    );
  }

  for (auto it = m_devices.begin(); it != m_devices.end();) {
    if (!seen.contains(it->first)) {
      it = m_devices.erase(it);
    } else {
      ++it;
    }
  }
}
