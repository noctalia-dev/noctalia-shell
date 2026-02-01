pragma Singleton
import QtQuick

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

Singleton {
  id: root

  // MARK: BatteryService
  // Primary battery device (prioritizes laptop over Bluetooth)
  readonly property var primaryDevice: _laptopBattery || _bluetoothBattery || null
  // Whether the primary device is a laptop battery
  readonly property bool isLaptopBattery: _laptopBattery !== null && primaryDevice === _laptopBattery
  readonly property real batteryPercentage: getPercentage(primaryDevice)
  readonly property bool batteryCharging: isCharging(primaryDevice)
  readonly property bool batteryPluggedIn: isPluggedIn(primaryDevice)
  readonly property bool batteryReady: isDeviceReady(primaryDevice)
  readonly property bool batteryPresent: isDevicePresent(primaryDevice)

  property bool healthAvailable: false
  property int healthPercent: -1

  readonly property var _laptopBattery: {
    if (!UPower.devices) {
      return UPower.displayDevice;
    }

    var devices = UPower.devices.values || [];

    // 1. Explicitly look for BAT0 first
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i];
      if (d && (d.nativePath === "BAT0" || d.objectPath === "/org/freedesktop/UPower/devices/battery_BAT0")) {
        return d;
      }
    }

    // 2. Fallback to displayDevice if it's a laptop battery
    if (UPower.displayDevice && UPower.displayDevice.isLaptopBattery) {
      return UPower.displayDevice;
    }

    // 3. Any other device marked as a laptop battery
    for (var j = 0; j < devices.length; j++) {
      var device = devices[j];
      if (device && device.type === UPowerDeviceType.Battery && device.isLaptopBattery) {
        return device;
      }
    }

    if (UPower.displayDevice.isPresent) {
      return UPower.displayDevice;
    }
    return null;
  }

  readonly property var externalBatteries: {
    var list = [];
    var devices = BluetoothService.devices ? (BluetoothService.devices.values || []) : [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.connected && device.batteryAvailable) {
        list.push(device);
      }
    }
    return list;
  }

  readonly property var _bluetoothBattery: externalBatteries.length > 0 ? externalBatteries[0] : null

  // MARK: BatterySettings
  property var deviceModel: {
    var model = [
      {
        "key": "__default__",
        "name": I18n.tr("bar.battery.device-default")
      }
    ];
    // UPower Devices
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

  // MARK: findUPowerDevice
  function findUPowerDevice(nativePath) {
    if (!nativePath || nativePath === "__default__" || nativePath === "DisplayDevice") {
      return _laptopBattery;
    }

    if (!UPower.devices) {
      return null;
    }

    var deviceArray = UPower.devices.values || [];
    for (var i = 0; i < deviceArray.length; i++) {
      var device = deviceArray[i];
      if (device && device.nativePath === nativePath) {
        if (device.type === UPowerDeviceType.LinePower) {
          continue;
        }
        return device;
      }
    }
    return null;
  }

  // MARK: findBluetoothDevice
  function findBluetoothDevice(nativePath) {
    if (!nativePath || !BluetoothService.devices) {
      return null;
    }

    var macMatch = nativePath.match(/([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})/);
    if (!macMatch) {
      return null;
    }

    var macAddress = macMatch[1].toUpperCase();
    var deviceArray = BluetoothService.devices.values || [];

    for (var i = 0; i < deviceArray.length; i++) {
      var device = deviceArray[i];
      if (device && device.address && device.address.toUpperCase() === macAddress) {
        return device;
      }
    }
    return null;
  }

  // MARK: isDevicePresent
  function isDevicePresent(device) {
    if (!device) {
      return false;
    }

    // Handle Bluetooth devices (identified by having batteryAvailable property)
    if (device.batteryAvailable !== undefined) {
      return device.connected === true;
    }

    // Handle UPower devices
    if (device.type !== undefined) {
      if (device.type === UPowerDeviceType.Battery && device.isPresent !== undefined) {
        return device.isPresent === true;
      }
      // Fallback for non-battery UPower devices or if isPresent is missing
      return device.ready && device.percentage !== undefined;
    }
    return false;
  }

  // MARK: isDeviceReady
  function isDeviceReady(device) {
    if (!isDevicePresent(device)) {
      return false;
    }
    if (device.batteryAvailable !== undefined) {
      return device.battery !== undefined;
    }
    return device.ready && device.percentage !== undefined;
  }

  // MARK: getPercentage
  function getPercentage(device) {
    if (!device) {
      return -1;
    }
    if (device.batteryAvailable !== undefined) {
      return (device.battery || 0) * 100;
    }
    return (device.percentage || 0) * 100;
  }

  // MARK: isCharging
  function isCharging(device) {
    if (!device || isBluetoothDevice(device)) {
      // Tracking bluetooth devices can charge or not is a loop hole, none of my devices has it, even if it possible?!
      return false;  // Assuming not charging until someone/quickshell brings a way to do pretty unlikely.
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.Charging;
    }
    return false;
  }

  // MARK: isPluggedIn
  function isPluggedIn(device) {
    if (!device || isBluetoothDevice(device)) {
      // Tracking bluetooth devices can charge or not is a loop hole, none of my devices has it, even if it possible?!
      return false;  // Assuming not charging until someone/quickshell brings a way to do pretty unlikely.
    }
    if (device.state !== undefined) {
      return device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge;
    }
    return false;
  }

  // MARK: isBluetoothDevice
  function isBluetoothDevice(device) {
    return device && device.batteryAvailable !== undefined;
  }

  // MARK: getDeviceName
  function getDeviceName(device) {
    if (!isDeviceReady(device)) {
      return "";
    }

    // Don't show name for laptop batteries
    if (!isBluetoothDevice(device) && device.isLaptopBattery) {
      return "";
    }

    if (isBluetoothDevice(device) && device.name) {
      return device.name;
    }

    if (device.model) {
      return device.model;
    }

    return "";
  }

  // MARK: refreshHealth
  function refreshHealth() {
    if (!isLaptopBattery) {
      healthAvailable = false;
      healthPercent = -1;
      return;
    }
    healthProcess.running = true;
  }

  Process {
    id: healthProcess
    command: ["sh", "-c", `upower -i ${primaryDevice && primaryDevice.nativePath ? "/org/freedesktop/UPower/devices/battery_" + primaryDevice.nativePath : "$(upower -e | grep battery | head -n 1)"} 2>/dev/null | grep -iE 'capacity'`]
    environment: ({
                    "LC_ALL": "C"
                  })

    stdout: SplitParser {
      onRead: function (data) {
        var line = data.trim();
        if (line === "") {
          return;
        }
        var capacityMatch = line.match(/^\s*capacity:\s*(\d+(?:\.\d+)?)\s*%/i);
        if (capacityMatch) {
          root.healthPercent = Math.round(parseFloat(capacityMatch[1]));
          root.healthAvailable = true;
          Logger.d("Battery", "Health retrieved from CLI:", root.healthPercent + "%");
        }
      }
    }
  }

  Component.onCompleted: {
    if (isLaptopBattery) {
      Qt.callLater(refreshHealth);
    }
  }

  // MARK: getIcon
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
    if (percent >= 80) {
      return "battery-4";
    }
    if (percent >= 60) {
      return "battery-3";
    }
    if (percent >= 40) {
      return "battery-2";
    }
    if (percent >= 20) {
      return "battery-1";
    }
    if (percent >= 0) {
      return "battery";
    }
    return "battery-off"; // New fallback icon clearly represent if nothing is true here.
  }

  // MARK: hasAnyBattery
  function hasAnyBattery() {
    return primaryDevice !== null;
  }

  // MARK: Battery
  // MARK: getRateText
  function getRateText(device) {
    if (!device || device.changeRate === undefined) {
      return "";
    }
    const rate = Math.abs(device.changeRate);
    if (isPluggedIn(device)) {
      return I18n.tr("battery.plugged-in");
    } else if (device.timeToFull > 0) {
      return I18n.tr("battery.charging-rate", {
                       "rate": rate.toFixed(2)
                     });
    } else if (device.timeToEmpty > 0) {
      return I18n.tr("battery.discharging-rate", {
                       "rate": rate.toFixed(2)
                     });
    }
    return I18n.tr("common.idle");
  }

  // MARK: getTimeRemainingText
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
}
