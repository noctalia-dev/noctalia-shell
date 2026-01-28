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

  // 1. Centralized list of all batteries
  readonly property var devices: {
    var list = [];
    var seenPaths = new Set();

    // Add UPower batteries
    var upowerBatteryCount = 0;
    if (UPower.devices) {
      var upowerArray = UPower.devices.values || [];
      for (var i = 0; i < upowerArray.length; i++) {
        var d = upowerArray[i];
        if (isDevicePresent(d) && d.type === UPowerDeviceType.Battery) {
          if (d.nativePath && !seenPaths.has(d.nativePath)) {
            list.push(d);
            seenPaths.add(d.nativePath);
            upowerBatteryCount++;
          }
        }
      }
    }
    // Add DisplayDevice (Aggregate)
    if (UPower.displayDevice && UPower.displayDevice.type === UPowerDeviceType.Battery && isDevicePresent(UPower.displayDevice)) {
      if (upowerBatteryCount !== 1) {
        list.push(UPower.displayDevice);
      }
    }
    // Add Bluetooth batteries
    if (BluetoothService.devices) {
      var btArray = BluetoothService.devices.values || [];
      for (var j = 0; j < btArray.length; j++) {
        var btd = btArray[j];
        if (isDevicePresent(btd) && btd.batteryAvailable) {
          // Bluetooth devices use address as unique ID
          if (btd.address && !seenPaths.has(btd.address)) {
            list.push(btd);
            seenPaths.add(btd.address);
          }
        }
      }
    }
    return list;
  }

  // 2. Determine the primary device (System Battery)
  readonly property var primaryDevice: {
    if (devices.length === 0)
    return null;

    // Prioritize DisplayDevice (Aggregate)
    if (UPower.displayDevice && UPower.displayDevice.type === UPowerDeviceType.Battery && isDevicePresent(UPower.displayDevice)) {
      return UPower.displayDevice;
    }

    // Prioritize BAT0
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i];
      if (d && (d.nativePath === "BAT0" || d.objectPath === "/org/freedesktop/UPower/devices/battery_BAT0")) {
        return d;
      }
    }

    // Prioritize (any) Laptop Battery
    for (var j = 0; j < devices.length; j++) {
      var dev = devices[j];
      if (dev && !isBluetoothDevice(dev) && dev.isLaptopBattery) {
        return dev;
      }
    }

    // Fallback to the first available device
    return devices[0];
  }

  // Whether the primary device is a laptop battery
  readonly property bool isLaptopBattery: primaryDevice !== null && !isBluetoothDevice(primaryDevice) && primaryDevice.isLaptopBattery

  // Global properties for the Primary Device (used by LockScreen etc)
  readonly property real batteryPercentage: getPercentage(primaryDevice)
  readonly property bool batteryCharging: isCharging(primaryDevice)
  readonly property bool batteryPluggedIn: isPluggedIn(primaryDevice)
  readonly property bool batteryReady: isDeviceReady(primaryDevice)
  readonly property bool batteryPresent: isDevicePresent(primaryDevice)

  // Exposed subsets of devices
  readonly property var laptopBatteries: devices.filter(d => !isBluetoothDevice(d))
  readonly property var externalBatteries: devices.filter(d => isBluetoothDevice(d))

  property bool healthAvailable: false
  property int healthPercent: -1

  // Initialization state
  property bool initializationComplete: false
  readonly property bool ready: initializationComplete

  Timer {
    interval: 500
    running: true
    repeat: false
    onTriggered: root.initializationComplete = true
  }

  // 3. Helper to resolve a device by path, or return primary if path is empty/invalid
  function resolveDevice(nativePath) {
    if (!nativePath || nativePath === "") {
      return primaryDevice;
    }

    // Check for DisplayDevice explicitly if requested via "DisplayDevice" or empty string
    if (nativePath === "DisplayDevice" && UPower.displayDevice) {
      return UPower.displayDevice;
    }

    // Search in our cached list
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i];
      if (isBluetoothDevice(d)) {
        if (d.address && d.address.toUpperCase() === nativePath.toUpperCase())
          return d;
        // Try matching MAC in path string if passed format differs
        if (nativePath.includes(d.address.toUpperCase()))
          return d;
      } else {
        if (d.nativePath === nativePath)
          return d;
      }
    }
    return null;
  }

  function isDevicePresent(device) {
    if (!device)
      return false;

    // Handle Bluetooth devices
    if (device.batteryAvailable !== undefined) {
      return device.connected === true;
    }

    // Handle UPower devices
    if (device.type !== undefined) {
      if (device.type === UPowerDeviceType.Battery && device.isPresent !== undefined) {
        return device.isPresent === true;
      }
      return device.ready && device.percentage !== undefined;
    }
    return false;
  }

  function isDeviceReady(device) {
    if (!isDevicePresent(device))
      return false;

    if (device.batteryAvailable !== undefined) {
      return device.battery !== undefined;
    }
    return device.ready && device.percentage !== undefined;
  }

  function getPercentage(device) {
    if (!device)
      return 0;
    if (device.batteryAvailable !== undefined) {
      return (device.battery || 0) * 100;
    }
    return (device.percentage || 0) * 100;
  }

  function isCharging(device) {
    if (!device || device.batteryAvailable !== undefined)
      return false;
    return device.state === UPowerDeviceState.Charging;
  }

  function isPluggedIn(device) {
    if (!device || device.batteryAvailable !== undefined)
      return false;
    return device.state === UPowerDeviceState.FullyCharged || device.state === UPowerDeviceState.PendingCharge;
  }

  function isBluetoothDevice(device) {
    return device && device.batteryAvailable !== undefined;
  }

  function getDeviceName(device) {
    if (!isDeviceReady(device))
      return "";

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

  function getTimeRemainingText(device) {
    if (!ready || !isDevicePresent(device)) {
      return I18n.tr("battery.no-battery-detected");
    }
    if (isPluggedIn(device)) {
      return I18n.tr("battery.plugged-in");
    }
    if (device) {
      if (device.timeToFull > 0) {
        return I18n.tr("battery.time-until-full", {
                         "time": Time.formatVagueHumanReadableDuration(device.timeToFull)
                       });
      }
      if (device.timeToEmpty > 0) {
        return I18n.tr("battery.time-left", {
                         "time": Time.formatVagueHumanReadableDuration(device.timeToEmpty)
                       });
      }
    }
    return I18n.tr("common.idle");
  }

  function getDeviceOptionsModel() {
    var model = [
          {
            "key": "",
            "name": I18n.tr("bar.battery.device-default")
          }
        ];

    for (var i = 0; i < devices.length; i++) {
      var d = devices[i];
      var name = "";

      // Determine friendly name
      if (isBluetoothDevice(d)) {
        name = d.name || "Bluetooth Device";
      } else if (d === UPower.displayDevice) {
        name = I18n.tr("common.battery-aggregate") || "Display Device";
      } else {
        name = d.model || I18n.tr("common.battery");
      }

      // Determine ID/Path
      var key = isBluetoothDevice(d) ? d.address : d.nativePath;
      if (!key && d === UPower.displayDevice)
        key = "DisplayDevice";

      // Format: "Model (ID)"
      var displayName = name;
      if (key && key !== "DisplayDevice") {
        displayName = `${name} (${key})`;
      }

      model.push({
                   "key": key || "",
                   "name": displayName
                 });
    }
    return model;
  }

  function refreshHealth() {
    if (!isLaptopBattery || !primaryDevice) {
      healthAvailable = false;
      healthPercent = -1;
      return;
    }
    healthProcess.running = true;
  }

  Process {
    id: healthProcess
    // Dynamically target the primary device if possible, otherwise fall back to first battery
    command: ["sh", "-c", `upower -i ${primaryDevice && primaryDevice.nativePath ? "/org/freedesktop/UPower/devices/battery_" + primaryDevice.nativePath : "$(upower -e | grep battery | head -n 1)"} 2>/dev/null | grep -iE 'capacity'`]
    environment: ({
                    "LC_ALL": "C"
                  })

    stdout: SplitParser {
      onRead: function (data) {
        var line = data.trim();
        if (line === "")
          return;

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

  function hasAnyBattery() {
    return primaryDevice !== null;
  }
}
