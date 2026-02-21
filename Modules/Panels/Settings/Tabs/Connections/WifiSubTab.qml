import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Bluetooth

import qs.Commons
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  // Combined visibility check: tab must be visible AND the window must be visible
  //readonly property bool effectivelyVisible: root.visible && Window.window && Window.window.visible

  NBox {
    Layout.fillWidth: true
    Layout.preferredHeight: masterControlCol.implicitHeight + Style.margin2L
    color: Color.mSurface

    ColumnLayout {
      id: masterControlCol
      spacing: Style.marginL
      anchors.fill: parent
      anchors.margins: Style.marginL

      // Airplane Mode Toggle
      NToggle {
        Layout.fillWidth: true
        label: I18n.tr("toast.airplane-mode.title")
        icon: Settings.data.network.airplaneModeEnabled ? "plane" : "plane-off"
        checked: Settings.data.network.airplaneModeEnabled
        onToggled: checked => BluetoothService.setAirplaneMode(checked)
      }

      // Wi-Fi Master Control
      NToggle {
        Layout.fillWidth: true
        label: I18n.tr("common.wifi")
        icon: Settings.data.network.wifiEnabled ? "wifi" : "wifi-off"
        checked: Settings.data.network.wifiEnabled
        onToggled: checked => NetworkService.setWifiEnabled(checked)
        enabled: ProgramCheckerService.nmcliAvailable && !Settings.data.network.airplaneModeEnabled && NetworkService.wifiAvailable
      }
    }
  }
}
