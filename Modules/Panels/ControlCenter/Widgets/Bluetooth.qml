import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NIconButtonHot {
  property ShellScreen screen

  icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
  tooltipText: I18n.tr("quickSettings.bluetooth.tooltip.action")
  onClicked: {
    PanelService.getPanel("bluetoothPanel", screen)?.toggle(this)
  }
}
