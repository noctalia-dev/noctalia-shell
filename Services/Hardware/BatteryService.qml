pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

Singleton {
  id: root

  // Cached device lookups (computed once, used by all properties)
  readonly property var _laptopBattery: {
    if (UPower.displayDevice && UPower.displayDevice.isLaptopBattery) {
      return UPower.displayDevice;
    }
    var devices = UPower.devices ? (UPower.devices.values || []) : [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.type === UPowerDeviceType.Battery && device.isLaptopBattery && device.percentage !== undefined) {
        return device;
      }
    }
    return null;
  }

  readonly property var _bluetoothBattery: {
    var devices = BluetoothService.devices ? (BluetoothService.devices.values || []) : [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.connected && device.batteryAvailable && device.battery !== undefined) {
        return device;
      }
    }
    return null;
  }

  // Primary battery device (prioritizes laptop over Bluetooth)
  readonly property var primaryDevice: _laptopBattery || _bluetoothBattery || null

  // Whether the primary device is a laptop battery
  readonly property bool isLaptopBattery: _laptopBattery !== null

  readonly property real batteryPercentage: {
    if (!primaryDevice) {
      return 0;
    }
    if (isLaptopBattery) {
      return (primaryDevice.percentage || 0) * 100;
    }
    return (primaryDevice.battery || 0) * 100;
  }

  readonly property bool batteryCharging: {
    if (!primaryDevice || !isLaptopBattery) {
      return false;
    }
    return primaryDevice.state !== undefined && primaryDevice.state === UPowerDeviceState.Charging;
  }

  readonly property bool batteryReady: {
    if (!primaryDevice) {
      return false;
    }
    if (isLaptopBattery) {
      return (primaryDevice.ready === true) && primaryDevice.percentage !== undefined;
    }
    return (primaryDevice.connected === true) && (primaryDevice.batteryAvailable === true) && primaryDevice.battery !== undefined;
  }

  readonly property bool batteryPresent: {
    if (!primaryDevice) {
      return false;
    }
    if (isLaptopBattery) {
      var hasIsPresent = primaryDevice.type === UPowerDeviceType.Battery && primaryDevice.isPresent !== undefined;
      return hasIsPresent ? (primaryDevice.isPresent === true) : (primaryDevice.ready && primaryDevice.percentage !== undefined);
    }
    return primaryDevice.connected === true;
  }

  property bool healthAvailable: false
  property int healthPercent: -1
  property string capacityLevel: ""

  function refreshHealth() {
    if (!isLaptopBattery || !primaryDevice) {
      healthAvailable = false;
      healthPercent = -1;
      capacityLevel = "";
      return;
    }
    healthProcess.running = true;
  }

  Process {
    id: healthProcess
    command: ["sh", "-c", "upower -i $(upower -e | grep battery | head -n 1) 2>/dev/null | grep -iE 'capacity'"]
    stdout: SplitParser {
      onRead: function(data) {
        var line = data.trim();
        if (line === "") return;

        var capacityMatch = line.match(/^\s*capacity:\s*(\d+(?:\.\d+)?)\s*%/i);
        if (capacityMatch) {
          root.healthPercent = Math.round(parseFloat(capacityMatch[1]));
          root.healthAvailable = true;
          Logger.d("Battery", "Health retrieved from CLI:", root.healthPercent + "%");
        }

        var levelMatch = line.match(/^\s*capacity-level:\s*(.+)/i);
        if (levelMatch) {
          root.capacityLevel = levelMatch[1].trim();
          Logger.d("Battery", "Capacity level:", root.capacityLevel);
        }
      }
    }
  }

  Timer {
    id: healthRefreshTimer
    interval: 60000
    running: root.isLaptopBattery
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshHealth()
  }

  onPrimaryDeviceChanged: {
    if (primaryDevice) {
      Qt.callLater(refreshHealth);
    }
  }

  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return "battery-exclamation";
    }
    if (charging) {
      return "common.charging";
    }
    if (percent >= 90) {
      return "battery-4";
    }
    if (percent >= 50) {
      return "battery-3";
    }
    if (percent >= 25) {
      return "battery-2";
    }
    if (percent >= 0) {
      return "battery-1";
    }
    return "battery";
  }

  function hasAnyBattery() {
    return primaryDevice !== null;
  }
}
