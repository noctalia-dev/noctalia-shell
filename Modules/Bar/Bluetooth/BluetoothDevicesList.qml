import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root

  property string label: ""
  property string tooltipText: ""
  property var model: {

  }

  Layout.fillWidth: true
  spacing: Style.marginM

  NText {
    text: root.label
    pointSize: Style.fontSizeL
    color: Color.mSecondary
    font.weight: Style.fontWeightMedium
    Layout.fillWidth: true
    visible: root.model.length > 0
  }

  Repeater {
    id: deviceList
    Layout.fillWidth: true
    model: root.model
    visible: BluetoothService.adapter && BluetoothService.adapter.enabled

    Rectangle {
      id: device

      readonly property bool canConnect: BluetoothService.canConnect(modelData)
      readonly property bool canDisconnect: BluetoothService.canDisconnect(modelData)
      readonly property bool isBusy: BluetoothService.isDeviceBusy(modelData)

      function getContentColor(defaultColor = Color.mOnSurface) {
        if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
          return Color.mPrimary
        if (modelData.blocked)
          return Color.mError
        return defaultColor
      }

      Layout.fillWidth: true
      Layout.preferredHeight: deviceLayout.implicitHeight + (Style.marginM * 2)
      radius: Style.radiusM
      color: Color.mSurface
      border.width: Math.max(1, Style.borderS)
      border.color: getContentColor(Color.mOutline)

      RowLayout {
        id: deviceLayout
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginM
        Layout.alignment: Qt.AlignVCenter

        // One device BT icon
        NIcon {
          icon: BluetoothService.getDeviceIcon(modelData)
          pointSize: Style.fontSizeXXL
          color: getContentColor(Color.mOnSurface)
          Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXXS

          // Device name
          NText {
            text: modelData.name || modelData.deviceName
            pointSize: Style.fontSizeM
            font.weight: Style.fontWeightMedium
            elide: Text.ElideRight
            color: getContentColor(Color.mOnSurface)
            Layout.fillWidth: true
          }

          // Status
          NText {
            text: BluetoothService.getStatusString(modelData)
            visible: text !== ""
            pointSize: Style.fontSizeXS
            color: getContentColor(Color.mOnSurfaceVariant)
          }

          // Signal Strength
          RowLayout {
            visible: modelData.signalStrength !== undefined
            Layout.fillWidth: true
            spacing: Style.marginXS

            // Device signal strength - "Unknown" when not connected
            NText {
              text: BluetoothService.getSignalStrength(modelData)
              pointSize: Style.fontSizeXS
              color: getContentColor(Color.mOnSurfaceVariant)
            }

            NIcon {
              visible: modelData.signalStrength > 0 && !modelData.pairing && !modelData.blocked
              icon: BluetoothService.getSignalIcon(modelData)
              pointSize: Style.fontSizeXS
              color: getContentColor(Color.mOnSurface)
            }

            NText {
              visible: modelData.signalStrength > 0 && !modelData.pairing && !modelData.blocked
              text: (modelData.signalStrength !== undefined && modelData.signalStrength > 0) ? modelData.signalStrength + "%" : ""
              pointSize: Style.fontSizeXS
              color: getContentColor(Color.mOnSurface)
            }
          }

          // Battery
          NText {
            visible: modelData.batteryAvailable
            text: BluetoothService.getBattery(modelData)
            pointSize: Style.fontSizeXS
            color: getContentColor(Color.mOnSurfaceVariant)
          }
        }

        // Spacer to push connect button to the right
        Item {
          Layout.fillWidth: true
        }

        // Call to action
        NButton {
          id: button
          visible: (modelData.state !== BluetoothDeviceState.Connecting)
          enabled: (canConnect || canDisconnect) && !isBusy
          outlined: !button.hovered
          fontSize: Style.fontSizeXS
          fontWeight: Style.fontWeightMedium
          backgroundColor: {
            if (device.canDisconnect && !isBusy) {
              return Color.mError
            }
            return Color.mPrimary
          }
          tooltipText: root.tooltipText
          text: {
            if (modelData.pairing) {
              return "Pairing..."
            }
            if (modelData.blocked) {
              return "Blocked"
            }
            if (modelData.connected) {
              return "Disconnect"
            }
            return "Connect"
          }
          icon: (isBusy ? "busy" : null)
          onClicked: {
            if (modelData.connected) {
              BluetoothService.disconnectDevice(modelData)
            } else {
              BluetoothService.connectDeviceWithTrust(modelData)
            }
          }
          onRightClicked: {
            BluetoothService.forgetDevice(modelData)
          }
        }
      }
    }
  }
}
