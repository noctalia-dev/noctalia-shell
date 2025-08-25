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

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  visible: Settings.data.network.bluetoothEnabled
  sizeMultiplier: 0.8
  colorBg: Color.mSurfaceVariant
  colorFg: Color.mOnSurface
  colorBorder: Color.transparent
  colorBorderHover: Color.transparent

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
  onClicked: PanelService.getPanel("bluetoothPanel")?.toggle(screen)
}
