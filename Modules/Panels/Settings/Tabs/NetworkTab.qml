import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL

  NHeader {
    description: I18n.tr("settings.network.section.description")
  }

  NToggle {
    label: I18n.tr("settings.network.wifi.label")
    description: I18n.tr("settings.network.wifi.description")
    checked: ProgramCheckerService.nmcliAvailable && Settings.data.network.wifiEnabled
    onToggled: checked => NetworkService.setWifiEnabled(checked)
    enabled: ProgramCheckerService.nmcliAvailable
  }

  NDivider {
    Layout.fillWidth: true
  }

  // Bluetooth adapter toggle grouped with its panel settings
  NToggle {
    label: I18n.tr("settings.network.bluetooth.label")
    description: I18n.tr("settings.network.bluetooth.description")
    checked: BluetoothService.enabled
    onToggled: checked => BluetoothService.setBluetoothEnabled(checked)
  }

  // Bluetooth signal strength polling (RSSI via bluetoothctl)
  NToggle {
    label: I18n.tr("settings.network.bluetooth.rssi-polling.label")
    description: I18n.tr("settings.network.bluetooth.rssi-polling.description")
    checked: Settings.data && Settings.data.network && Settings.data.network.bluetoothRssiPollingEnabled
    enabled: BluetoothService.enabled
    onToggled: checked => Settings.data.network.bluetoothRssiPollingEnabled = checked
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
