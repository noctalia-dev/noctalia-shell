import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

NIconButton {
  id: root

  readonly property bool bluetoothEnabled: Settings.data.network.bluetoothEnabled
  sizeMultiplier: 0.8
  showBorder: false
  visible: bluetoothEnabled

  icon: {
    // Show different icons based on connection status
    if (BluetoothService.pairedDevices.length > 0) {
      return "bluetooth_connected"
    } else if (BluetoothService.discovering) {
      return "bluetooth_searching"
    } else {
      return "bluetooth"
    }
  }
  tooltipText: "Bluetooth Devices"
  onClicked: {
    if (!bluetoothMenuLoader.active) {
      bluetoothMenuLoader.isLoaded = true
    }
    if (bluetoothMenuLoader.item) {
      if (bluetoothMenuLoader.item.visible) {
        // Panel is visible, hide it with animation
        if (bluetoothMenuLoader.item.hide) {
          bluetoothMenuLoader.item.hide()
        } else {
          bluetoothMenuLoader.item.visible = false
        }
      } else {
        // Panel is hidden, show it
        bluetoothMenuLoader.item.visible = true
      }
    }
  }

  BluetoothMenu {
    id: bluetoothMenuLoader
  }
}
