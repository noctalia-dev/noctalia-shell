pragma Singleton
import QtQml
import QtQuick

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  readonly property var primaryDevice: _laptopBattery || _peripheralBattery || null // Primary battery device (prioritizes laptop over peripherals)
  readonly property real batteryPercentage: getPercentage(primaryDevice)
  readonly property bool batteryCharging: isCharging(primaryDevice)
  readonly property bool batteryPluggedIn: isPluggedIn(primaryDevice)
  readonly property bool batteryReady: isDeviceReady(primaryDevice)
  readonly property bool batteryPresent: isDevicePresent(primaryDevice)
  readonly property real warningThreshold: Settings.data.systemMonitor.batteryWarningThreshold
  readonly property real criticalThreshold: Settings.data.systemMonitor.batteryCriticalThreshold
  readonly property string batteryIcon: getIcon(batteryPercentage, batteryCharging, batteryPluggedIn, batteryReady)

  readonly property var laptopBatteries: UPower.devices.values.filter(d => d.isLaptopBattery).sort((x, y) => {
                                                                                                     // Force DisplayDevice to the top
                                                                                                     if (x.nativePath.includes("DisplayDevice"))
                                                                                                     return -1;
                                                                                                     if (y.nativePath.includes("DisplayDevice"))
                                                                                                     return 1;

                                                                                                     // Standard string comparison works for BAT0 vs BAT1
                                                                                                     return x.nativePath.localeCompare(y.nativePath, undefined, {
                                                                                                                                         numeric: true
                                                                                                                                       });
                                                                                                   })

  readonly property var peripheralBatteries: UPower.devices.values.filter(d => d && isPeripheral(d) && isDeviceReady(d)).sort((x, y) => x.percentage - y.percentage)
  readonly property var _laptopBattery: UPower.displayDevice.isPresent ? UPower.displayDevice : (laptopBatteries.length > 0 ? laptopBatteries[0] : null)
  readonly property var _peripheralBattery: peripheralBatteries.length > 0 ? peripheralBatteries[0] : null

  property var deviceModel: {
    var model = [
      {
        "key": "__default__",
        "name": I18n.tr("bar.battery.device-default")
      }
    ];
    const devices = UPower.devices?.values || [];
    for (let d of devices) {
      if (!d || d.type === UPowerDeviceType.LinePower) {
        continue;
      }
      model.push({
                   key: d.nativePath || "",
                   name: d.model || d.nativePath || I18n.tr("common.unknown")
                 });
    }
    return model;
  }

  property var _hasNotified: ({})

  function findDevice(nativePath) {
    if (!nativePath || nativePath === "__default__" || nativePath === "DisplayDevice") {
      return _laptopBattery;
    }

    if (!UPower.devices) {
      return null;
    }

    const devices = UPower.devices?.values || [];
    for (let d of devices) {
      if (d && d.nativePath === nativePath) {
        if (d.type === UPowerDeviceType.LinePower) {
          continue;
        }
        return d;
      }
    }
    return null;
  }

  function isDevicePresent(device) {
    if (!device) {
      return false;
    }

    // Handle UPower devices
    if (device.type !== undefined) {
      if (device.isPresent !== undefined) {
        return device.isPresent === true;
      }
      // Fallback for non-battery UPower devices or if isPresent is missing
      return device.ready && device.percentage !== undefined;
    }
    return false;
  }

  function isDeviceReady(device) {
    if (!isDevicePresent(device)) {
      return false;
    }
    return device.ready && device.percentage !== undefined;
  }

  function getPercentage(device) {
    if (!device) {
      return -1;
    }
    const z = device.percentage || 0;
    return Math.round(z > 1.0 ? z : z * 100);
  }

  function isCharging(device) {
    if (!device) {
      return false;
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.Charging;
    }
    return false;
  }

  function isPluggedIn(device) {
    if (!device) {
      return false;
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge;
    }
    return false;
  }

  function isCriticalBattery(device) {
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= criticalThreshold;
  }

  function isLowBattery(device) {
    return (!isCharging(device) && !isPluggedIn(device)) && getPercentage(device) <= warningThreshold && getPercentage(device) > criticalThreshold;
  }

  function isPeripheral(device) {
    if (!device) {
      return false;
    }
    // Anything that isn't a main laptop battery or line power is a peripheral for our UI purposes
    return !device.isLaptopBattery && device.type !== UPowerDeviceType.LinePower;
  }

  function getDeviceName(device) {
    if (!isDeviceReady(device)) {
      return "";
    }

    if (!isPeripheral(device) && device.isLaptopBattery) {
      // If there is more than one battery explicitly name them
      // Logger.e("BatteryDebug", "Available Battery count: " + laptopBatteries.length); // can be useful for debugging
      if (laptopBatteries.length > 1 && device.nativePath) {
        if (device.nativePath.includes("DisplayDevice")) {
          return I18n.tr("battery.all-batteries");
        }
        var match = device.nativePath.match(/(\d+)$/);
        if (match) {
          // In case of 2 batteries: bat0 => bat1  bat1 => bat2
          return I18n.tr("common.battery") + " " + (parseInt(match[1]) + 1);  // Append numbers
        }
      }
      // Return Battery if there is only one
      return I18n.tr("common.battery");
    }
    return device.name || device.deviceName || device.model || "";
  }

  function getIcon(percent, charging, pluggedIn, isReady) {
    if (!isReady) {
      return "battery-exclamation";
    }
    if (charging) {
      return "battery-charging";
    }
    if (pluggedIn) {
      return "battery-charging-2";
    }

    const icons = [
            {
              threshold: 86,
              icon: "battery-4"
            },
            {
              threshold: 56,
              icon: "battery-3"
            },
            {
              threshold: 31,
              icon: "battery-2"
            },
            {
              threshold: 11,
              icon: "battery-1"
            },
            {
              threshold: 0,
              icon: "battery"
            }
          ];

    const match = icons.find(tier => percent >= tier.threshold);
    return match ? match.icon : "battery-off"; // New fallback icon clearly represent if nothing is true here.
  }

  function getRateText(device) {
    if (!device || device.changeRate === undefined) {
      return "";
    }
    const rate = Math.abs(device.changeRate);
    if (device.timeToFull > 0) {
      return I18n.tr("battery.charging-rate", {
                       "rate": rate.toFixed(2)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.discharging-rate", {
                       "rate": rate.toFixed(2)
                     });
    }
  }

  function getTimeRemainingText(device) {
    if (!isDeviceReady(device)) {
      return I18n.tr("battery.no-battery-detected");
    }
    if (isPluggedIn(device)) {
      return I18n.tr("battery.plugged-in");
    } else if (device.timeToFull > 0) {
      return I18n.tr("battery.time-until-full", {
                       "time": Time.formatVagueHumanReadableDuration(device.timeToFull)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.time-left", {
                       "time": Time.formatVagueHumanReadableDuration(device.timeToEmpty)
                     });
    }
    return I18n.tr("common.idle");
  }

  function checkDevice(device) {
    if (!device || !isDeviceReady(device)) {
      return;
    }

    const percentage = getPercentage(device);
    const charging = isCharging(device);
    const pluggedIn = isPluggedIn(device);
    const level = isLowBattery(device) ? "low" : (isCriticalBattery(device) ? "critical" : "");
    var deviceKey = device.nativePath || "";

    if (!_hasNotified[deviceKey]) {
      _hasNotified[deviceKey] = {
        low: false,
        critical: false
      };
    }

    if (charging || pluggedIn) {
      _hasNotified[deviceKey].low = false;
      _hasNotified[deviceKey].critical = false;
    }

    if (percentage > warningThreshold) {
      _hasNotified[deviceKey].low = false;
      _hasNotified[deviceKey].critical = false;
    } else if (percentage > criticalThreshold) {
      _hasNotified[deviceKey].critical = false;
    }

    if (level) {
      if (!_hasNotified[deviceKey][level]) {
        notify(device, level);
        _hasNotified[deviceKey][level] = true;
      }
    }
  }

  function notify(device, level) {
    if (!Settings.data.notifications.enableBatteryToast) {
      return;
    }
    var name = getDeviceName(device);
    var titleKey = level === "critical" ? "toast.battery.critical" : "toast.battery.low";
    var descKey = level === "critical" ? "toast.battery.critical-desc" : "toast.battery.low-desc";

    var title = I18n.tr(titleKey);
    var desc = I18n.tr(descKey, {
                         "percent": getPercentage(device)
                       });
    var icon = level === "critical" ? "battery-exclamation" : "battery-charging-2";

    if (isPeripheral(device) && name) {
      title = title + " " + name;
    }

    // Only 'showNotice' supports custom icons
    ToastService.showNotice(title, desc, icon, 6000);
  }

  function getDeviceIcon(device) {
    if (!device) {
      return "bt-device-generic";
    }

    const name = (device.model || device.deviceName || device.name || "").toLowerCase();
    const nativePath = (device.nativePath || "").toLowerCase();

    // 1. High-precision sub-types from the model name (e.g., "AirPods" should be earbuds, not just a headset)
    if (name.includes("pod") || name.includes("bud") || name.includes("minor"))
      return "bt-device-earbuds";
    if (name.includes("arctis") || name.includes("major"))
      return "bt-device-headset";

    // 2. Broad categories from the UPower object path (very reliable for basic device types)
    if (nativePath.includes("mouse"))
      return "bt-device-mouse";
    if (nativePath.includes("keyboard"))
      return "bt-device-keyboard";
    if (nativePath.includes("phone"))
      return "bt-device-phone";
    if (nativePath.includes("headset"))
      return "bt-device-headset";
    if (nativePath.includes("headphones"))
      return "bt-device-headphones";
    if (nativePath.includes("gaming_input") || nativePath.includes("controller") || nativePath.includes("joypad"))
      return "bt-device-gamepad";
    if (nativePath.includes("tablet"))
      return "bt-device-tablet";
    if (nativePath.includes("watch"))
      return "bt-device-watch";
    if (nativePath.includes("speaker") || nativePath.includes("audio") || nativePath.includes("sound"))
      return "bt-device-speaker";

    // 3. Fallback to UPowerDeviceType enum - Less reliable due lacks variety (e.g., all headphones are just "headset" in the enum, no distinction for earbuds)
    if (device.type !== undefined) {
      switch (device.type) {
      case UPowerDeviceType.Mouse:
        return "bt-device-mouse";
      case UPowerDeviceType.Keyboard:
        return "bt-device-keyboard";
      case UPowerDeviceType.Headset:
        return "bt-device-headset";
      case UPowerDeviceType.Phone:
        return "bt-device-phone";
      case UPowerDeviceType.Tablet:
        return "bt-device-tablet";
      case UPowerDeviceType.GamingInput:
        return "bt-device-gamepad";
      case UPowerDeviceType.Speakers:
        return "bt-device-speaker";
      case UPowerDeviceType.MediaPlayer:
        return "bt-device-speaker";
      }
    }

    // The last resort if nothing else matches - generic battery icon
    return getIcon(getPercentage(device), isCharging(device), isPluggedIn(device), isDeviceReady(device));
  }

  Instantiator {
    model: deviceModel
    delegate: Connections {
      required property var modelData
      property var device: findDevice(modelData.key)
      target: device

      function onPercentageChanged() {
        if (device.isLaptopBattery && modelData.key !== "__default__") {
          return;
        }
        checkDevice(device);
      }
      function onStateChanged() {
        if (device.isLaptopBattery && modelData.key !== "__default__") {
          return;
        }
        checkDevice(device);
      }
    }
  }
}
