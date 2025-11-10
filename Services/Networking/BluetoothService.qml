pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Singleton {
  id: root

  property bool airplaneModeToggled: false
  property bool lastBluetoothBlocked: false
  readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
  readonly property int state: adapter?.state ?? 0
  readonly property bool available: (adapter !== null)
  readonly property bool enabled: adapter?.enabled ?? false
  readonly property bool blocked: (adapter?.state === BluetoothAdapterState.Blocked)
  readonly property bool discovering: (adapter && adapter.discovering) ?? false
  readonly property var devices: adapter ? adapter.devices : null
  readonly property var pairedDevices: {
    if (!adapter || !adapter.devices) {
      return []
    }
    return adapter.devices.values.filter(dev => {
                                           return dev && (dev.paired || dev.trusted)
                                         })
  }
  readonly property var connectedDevices: {
    if (!adapter || !adapter.devices) {
      return []
    }
    return adapter.devices.values.filter(dev => dev && dev.connected)
  }

  readonly property var allDevicesWithBattery: {
    if (!adapter || !adapter.devices) {
      return []
    }
    return adapter.devices.values.filter(dev => {
                                           return dev && dev.batteryAvailable && dev.battery > 0
                                         })
  }

  function init() {
    Logger.i("Bluetooth", "Service started")
  }

  Timer {
    id: discoveryTimer
    interval: 1000
    repeat: false
    onTriggered: adapter.discovering = true
  }

  Connections {
    target: adapter
    function onStateChanged() {
      if (!adapter) {
        Logger.w("Bluetooth", "onStateChanged", "No adapter available")
        return
      }
      if (adapter.state === BluetoothAdapterState.Enabling || adapter.state === BluetoothAdapterState.Disabling) {
        return
      }

      Logger.d("Bluetooth", "onStateChanged", adapter.state)
      const bluetoothBlockedToggled = (root.blocked !== lastBluetoothBlocked)
      root.lastBluetoothBlocked = root.blocked
      if (bluetoothBlockedToggled) {
        checkWifiBlocked.running = true
      } else if (adapter.enabled) {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.enabled"), "bluetooth")
        discoveryTimer.running = true
      } else {
        ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disabled"), "bluetooth-off")
      }
    }
  }

  function sortDevices(devices) {
    return devices.sort((a, b) => {
                          var aName = a.name || a.deviceName || ""
                          var bName = b.name || b.deviceName || ""

                          var aHasRealName = aName.includes(" ") && aName.length > 3
                          var bHasRealName = bName.includes(" ") && bName.length > 3

                          if (aHasRealName && !bHasRealName)
                          return -1
                          if (!aHasRealName && bHasRealName)
                          return 1

                          var aSignal = (a.signalStrength !== undefined && a.signalStrength > 0) ? a.signalStrength : 0
                          var bSignal = (b.signalStrength !== undefined && b.signalStrength > 0) ? b.signalStrength : 0
                          return bSignal - aSignal
                        })
  }

  function getDeviceIcon(device) {
    if (!device) {
      return "bt-device-generic"
    }

    var name = (device.name || device.deviceName || "").toLowerCase()
    var icon = (device.icon || "").toLowerCase()
    if (icon.includes("headset") || icon.includes("audio") || name.includes("headphone") || name.includes("airpod") || name.includes("headset") || name.includes("arctis")) {
      return "bt-device-headphones"
    }

    if (icon.includes("mouse") || name.includes("mouse")) {
      return "bt-device-mouse"
    }
    if (icon.includes("keyboard") || name.includes("keyboard")) {
      return "bt-device-keyboard"
    }
    if (icon.includes("phone") || name.includes("phone") || name.includes("iphone") || name.includes("android") || name.includes("samsung")) {
      return "bt-device-phone"
    }
    if (icon.includes("watch") || name.includes("watch")) {
      return "bt-device-watch"
    }
    if (icon.includes("speaker") || name.includes("speaker")) {
      return "bt-device-speaker"
    }
    if (icon.includes("display") || name.includes("tv")) {
      return "bt-device-tv"
    }
    return "bt-device-generic"
  }

  function canConnect(device) {
    if (!device)
      return false


    /*
      Paired
      Means you’ve successfully exchanged keys with the device.
      The devices remember each other and can authenticate without repeating the pairing process.
      Example: once your headphones are paired, you don’t need to type a PIN every time.
      Hence, instead of !device.paired, should be device.connected
    */
    return !device.connected && !device.pairing && !device.blocked
  }

  function canDisconnect(device) {
    if (!device)
      return false
    return device.connected && !device.pairing && !device.blocked
  }

  function getStatusString(device) {
    if (device.state === BluetoothDeviceState.Connecting) {
      return "Connecting..."
    }
    if (device.pairing) {
      return "Pairing..."
    }
    if (device.blocked) {
      return "Blocked"
    }
    return ""
  }

  function getSignalStrength(device) {
    if (!device || device.signalStrength === undefined || device.signalStrength <= 0) {
      return "Signal: Unknown"
    }
    var signal = device.signalStrength
    if (signal >= 80) {
      return "Signal: Excellent"
    }
    if (signal >= 60) {
      return "Signal: Good"
    }
    if (signal >= 40) {
      return "Signal: Fair"
    }
    if (signal >= 20) {
      return "Signal: Poor"
    }
    return "Signal: Very poor"
  }

  function getBattery(device) {
    return `Battery: ${Math.round(device.battery * 100)}%`
  }

  function getSignalIcon(device) {
    if (!device || device.signalStrength === undefined || device.signalStrength <= 0) {
      return "antenna-bars-off"
    }
    var signal = device.signalStrength
    if (signal >= 80) {
      return "antenna-bars-5"
    }
    if (signal >= 60) {
      return "antenna-bars-4"
    }
    if (signal >= 40) {
      return "antenna-bars-3"
    }
    if (signal >= 20) {
      return "antenna-bars-2"
    }
    return "antenna-bars-1"
  }

  function isDeviceBusy(device) {
    if (!device) {
      return false
    }

    return device.pairing || device.state === BluetoothDeviceState.Disconnecting || device.state === BluetoothDeviceState.Connecting
  }

  function connectDeviceWithTrust(device) {
    if (!device) {
      return
    }

    device.trusted = true
    device.connect()
  }

  function disconnectDevice(device) {
    if (!device) {
      return
    }

    device.disconnect()
  }

  function forgetDevice(device) {
    if (!device) {
      return
    }

    device.trusted = false
    device.forget()
  }

  function setBluetoothEnabled(state) {
    if (!adapter) {
      Logger.w("Bluetooth", "No adapter available")
      return
    }

    Logger.i("Bluetooth", "SetBluetoothEnabled", state)
    adapter.enabled = state
  }

  Process {
    id: checkWifiBlocked
    running: false
    command: ["rfkill", "list", "wifi"]

    stdout: StdioCollector {
      onStreamFinished: {
        const wifiBlocked = text && text.trim().includes("Soft blocked: yes")
        Logger.d("Network", "Wi-Fi adapter was detected as blocked:", blocked)

        // Check if airplane mode has been toggled
        if (wifiBlocked && wifiBlocked === root.blocked) {
          root.airplaneModeToggled = true
          NetworkService.setWifiEnabled(false)
          ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("toast.airplane-mode.enabled"), "plane")
        } else if (!wifiBlocked && wifiBlocked === root.blocked) {
          root.airplaneModeToggled = true
          NetworkService.setWifiEnabled(true)
          ToastService.showNotice(I18n.tr("toast.airplane-mode.title"), I18n.tr("toast.airplane-mode.disabled"), "plane-off")
        } else if (adapter.enabled) {
          ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.enabled"), "bluetooth")
          discoveryTimer.running = true
        } else {
          ToastService.showNotice(I18n.tr("bluetooth.panel.title"), I18n.tr("toast.bluetooth.disabled"), "bluetooth-off")
        }
        root.airplaneModeToggled = false
      }
    }
  }
}
