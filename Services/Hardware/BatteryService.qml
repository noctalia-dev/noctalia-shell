pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Services.Networking
import qs.Services.UI

Singleton {
  id: root

  // Choose icon based on charge and charging state
  function getIcon(percent, charging, isReady) {
    if (!isReady) {
      return "battery-exclamation";
    }

    if (charging) {
      return "common.charging";
    } else {
      if (percent >= 90)
        return "battery-4";
      if (percent >= 50)
        return "battery-3";
      if (percent >= 25)
        return "battery-2";
      if (percent >= 0)
        return "battery-1";
      return "battery";
    }
  }

  // Find first connected Bluetooth device with battery (gamepad, etc.)
  function findBluetoothBatteryDevice() {
    if (!BluetoothService.devices) {
      return null;
    }
    var devices = BluetoothService.devices.values || [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.connected && device.batteryAvailable && device.battery !== undefined) {
        return device;
      }
    }
    return null;
  }

  // Find laptop battery device, only returns actual battery (not displayDevice as fallback)
  function findLaptopBattery() {
    // First check displayDevice if it's a laptop battery
    if (UPower.displayDevice && UPower.displayDevice.isLaptopBattery) {
      return UPower.displayDevice;
    }

    // Then search through all devices
    if (!UPower.devices) {
      return null;
    }

    var devices = UPower.devices.values || [];
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i];
      if (device && device.type === UPowerDeviceType.Battery && device.isLaptopBattery && device.percentage !== undefined) {
        return device;
      }
    }
    return null;
  }

  // Check if any battery is available (laptop or Bluetooth/gamepad)
  function hasAnyBattery() {
    var laptopBattery = findLaptopBattery();
    var bluetoothDevice = findBluetoothBatteryDevice();
    return (laptopBattery !== null) || (bluetoothDevice !== null);
  }
}
