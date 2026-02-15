import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: !BluetoothService.enabled ? "bluetooth-off" : ((BluetoothService.connectedDevices && BluetoothService.connectedDevices.length > 0) ? "bluetooth-connected" : "bluetooth")
  tooltipText: I18n.tr("common.bluetooth")
  onClicked: {
    var p = PanelService.getPanel("bluetoothPanel", screen);
    if (p)
      p.toggle(this);
  }
  onRightClicked: {
    if (!Settings.data.network.airplaneModeEnabled) {
      BluetoothService.setBluetoothEnabled(!BluetoothService.enabled);
    }
  }
}
