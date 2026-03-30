import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: !NetworkService.airplaneModeEnabled ? "plane-off" : "plane"
  hot: NetworkService.airplaneModeEnabled
  tooltipText: I18n.tr("toast.airplane-mode.title")
  onClicked: {
    NetworkService.setAirplaneMode(!NetworkService.airplaneModeEnabled);
  }
  enabled: NetworkService.wifiAvailable && BluetoothService.bluetoothAvailable
}
