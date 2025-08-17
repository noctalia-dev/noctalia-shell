import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import qs.Commons
import qs.Services
import qs.Widgets

// Loader for Bluetooth menu
NLoader {
  id: root

  content: Component {
    NPanel {
      id: bluetoothPanel

      function hide() {
        bluetoothMenuRect.scaleValue = 0.8
        bluetoothMenuRect.opacityValue = 0.0
        hideTimer.start()
      }

      // Connect to NPanel's dismissed signal to handle external close events
      Connections {
        target: bluetoothPanel
        ignoreUnknownSignals: true
        function onDismissed() {
          // Start hide animation
          bluetoothMenuRect.scaleValue = 0.8
          bluetoothMenuRect.opacityValue = 0.0
          // Hide after animation completes
          hideTimer.start()
        }
      }

      // Also handle visibility changes from external sources
      onVisibleChanged: {
        if (visible && Settings.data.network.bluetoothEnabled) {
          // Always refresh devices when menu opens to get fresh device objects
          BluetoothService.adapter.discovering = true
        } else if (bluetoothMenuRect.opacityValue > 0) {
          // Start hide animation
          bluetoothMenuRect.scaleValue = 0.8
          bluetoothMenuRect.opacityValue = 0.0
          // Hide after animation completes
          hideTimer.start()
        }
      }

      // Timer to hide panel after animation
      Timer {
        id: hideTimer
        interval: Style.animationSlow
        repeat: false
        onTriggered: {
          bluetoothPanel.visible = false
          bluetoothPanel.dismissed()
        }
      }

      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

      Rectangle {
        id: bluetoothMenuRect

        property var deviceData: null

        color: Color.mSurface
        radius: Style.radiusLarge * scaling
        border.color: Color.mOutlineVariant
        border.width: Math.max(1, Style.borderThin * scaling)
        width: 380 * scaling
        height: 500 * scaling
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.marginTiny * scaling
        anchors.rightMargin: Style.marginTiny * scaling

        // Animation properties
        property real scaleValue: 0.8
        property real opacityValue: 0.0

        scale: scaleValue
        opacity: opacityValue

        // Prevent closing the window if clicking inside it
        MouseArea {
          anchors.fill: parent
        }

        // Animate in when component is completed
        Component.onCompleted: {
          scaleValue = 1.0
          opacityValue = 1.0
        }

        // Animation behaviors
        Behavior on scale {
          NumberAnimation {
            duration: Style.animationSlow
            easing.type: Easing.OutExpo
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: Style.animationNormal
            easing.type: Easing.OutQuad
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginLarge * scaling
          spacing: Style.marginMedium * scaling

          // HEADER
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginMedium * scaling

            NText {
              text: "bluetooth"
              font.family: "Material Symbols Outlined"
              font.pointSize: Style.fontSizeXL * scaling
              color: Color.mPrimary
            }

            NText {
              text: "Bluetooth"
              font.pointSize: Style.fontSizeLarge * scaling
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NIconButton {
              icon: BluetoothService.adapter && BluetoothService.adapter.discovering ? "stop_circle" : "refresh"
              tooltipText: "Refresh Devices"
              sizeMultiplier: 0.8
              onClicked: {
                if (BluetoothService.adapter) {
                  BluetoothService.adapter.discovering = !BluetoothService.adapter.discovering
                }
              }
            }

            NIconButton {
              icon: "close"
              tooltipText: "Close"
              sizeMultiplier: 0.8
              onClicked: {
                bluetoothPanel.hide()
              }
            }
          }

          NDivider {}

          ScrollView {
            id: scrollView

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            // Available devices
            Column {
              id: column

              width: parent.width
              spacing: Style.marginMedium * scaling
              visible: BluetoothService.adapter && BluetoothService.adapter.enabled

              RowLayout {
                width: parent.width
                spacing: Style.marginMedium * scaling

                NText {
                  text: "Available Devices"
                  font.pointSize: Style.fontSizeLarge * scaling
                  color: Color.mOnSurface
                  font.weight: Style.fontWeightMedium
                }
              }

              Repeater {
                model: {
                  if (!BluetoothService.adapter || !BluetoothService.adapter.discovering || !Bluetooth.devices)
                    return []

                  var filtered = Bluetooth.devices.values.filter(dev => {
                                                                   return dev && !dev.paired && !dev.pairing
                                                                   && !dev.blocked && (dev.signalStrength === undefined
                                                                                       || dev.signalStrength > 0)
                                                                 })
                  return BluetoothService.sortDevices(filtered)
                }

                Rectangle {
                  property bool canConnect: BluetoothService.canConnect(modelData)
                  property bool isBusy: BluetoothService.isDeviceBusy(modelData)

                  width: parent.width
                  height: 70
                  radius: Style.radiusMedium * scaling
                  color: {
                    if (availableDeviceArea.containsMouse && !isBusy)
                      return Color.mTertiary

                    if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
                      return Color.mPrimary

                    if (modelData.blocked)
                      return Color.mError

                    return Color.mSurfaceVariant
                  }
                  border.color: Color.mOutline
                  border.width: Math.max(1, Style.borderThin * scaling)

                  Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.marginMedium * scaling
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.marginSmall * scaling

                    // One device BT icon
                    NText {
                      text: BluetoothService.getDeviceIcon(modelData)
                      font.family: "Material Symbols Outlined"
                      font.pointSize: Style.fontSizeXL * scaling
                      color: {
                        if (availableDeviceArea.containsMouse)
                          return Color.mOnTertiary

                        if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
                          return Color.mOnPrimary

                        if (modelData.blocked)
                          return Color.mOnError

                        return Color.mOnSurface
                      }
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      spacing: Style.marginTiniest * scaling
                      anchors.verticalCenter: parent.verticalCenter

                      // One device name
                      NText {
                        text: modelData.name || modelData.deviceName
                        font.pointSize: Style.fonttSizeMedium * scaling
                        elide: Text.ElideRight
                        color: {
                          if (availableDeviceArea.containsMouse)
                            return Color.mOnTertiary

                          if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
                            return Color.mOnPrimary

                          if (modelData.blocked)
                            return Color.mOnError

                          return Color.mOnSurface
                        }
                        font.weight: Style.fontWeightMedium
                      }

                      Row {
                        spacing: Style.marginTiny * scaling

                        Row {
                          spacing: Style.marginSmall * spacing

                          // One device signal strength - "Unknown" when not connected
                          NText {
                            text: {
                              if (modelData.pairing)
                                return "Pairing..."

                              if (modelData.blocked)
                                return "Blocked"

                              return BluetoothService.getSignalStrength(modelData)
                            }
                            font.pointSize: Style.fontSizeSmall * scaling
                            color: {
                              if (availableDeviceArea.containsMouse)
                                return Color.mOnTertiary

                              if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
                                return Color.mOnPrimary

                              if (modelData.blocked)
                                return Color.mOnError

                              return Color.mOnSurface
                            }
                          }

                          NText {
                            text: BluetoothService.getSignalIcon(modelData)
                            font.family: "Material Symbols Outlined"
                            font.pointSize: Style.fontSizeSmall * scaling
                            color: {
                              if (availableDeviceArea.containsMouse)
                                return Color.mOnTertiary

                              if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
                                return Color.mOnPrimary

                              if (modelData.blocked)
                                return Color.mOnError

                              return Color.mOnSurface
                            }
                            visible: modelData.signalStrength !== undefined && modelData.signalStrength > 0
                                     && !modelData.pairing && !modelData.blocked
                          }

                          NText {
                            text: (modelData.signalStrength !== undefined
                                   && modelData.signalStrength > 0) ? modelData.signalStrength + "%" : ""
                            font.pointSize: Style.fontSizeSmall * scaling
                            color: {
                              if (availableDeviceArea.containsMouse)
                                return Color.mOnTertiary

                              if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
                                return Color.mOnPrimary

                              if (modelData.blocked)
                                return Color.mOnError

                              return Color.mOnSurface
                            }
                            visible: modelData.signalStrength !== undefined && modelData.signalStrength > 0
                                     && !modelData.pairing && !modelData.blocked
                          }
                        }
                      }
                    }
                  }

                  Rectangle {
                    width: 80 * scaling
                    height: 28 * scaling
                    radius: Style.radiusMedium * scaling
                    anchors.right: parent.right
                    anchors.rightMargin: Style.marginMedium * scaling
                    anchors.verticalCenter: parent.verticalCenter
                    visible: modelData.state !== BluetoothDeviceState.Connecting
                    color: Color.transparent

                    border.color: {
                      if (availableDeviceArea.containsMouse) {
                        return Color.mOnTertiary
                      } else {
                        return Color.mPrimary
                      }
                    }
                    border.width: Math.max(1, Style.borderThin * scaling)
                    opacity: canConnect || isBusy ? 1 : 0.5

                    // On device connect button
                    NText {
                      anchors.centerIn: parent
                      text: {
                        if (modelData.pairing)
                          return "Pairing..."

                        if (modelData.blocked)
                          return "Blocked"

                        return "Connect"
                      }
                      font.pointSize: Style.fontSizeSmall * scaling
                      font.weight: Style.fontWeightMedium
                      color: {
                        if (availableDeviceArea.containsMouse) {
                          return Color.mOnTertiary
                        } else {
                          return Color.mPrimary
                        }
                      }
                    }
                  }

                  MouseArea {
                    id: availableDeviceArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: canConnect
                                 && !isBusy ? Qt.PointingHandCursor : (isBusy ? Qt.BusyCursor : Qt.ArrowCursor)
                    enabled: canConnect && !isBusy
                    onClicked: {
                      if (modelData)
                        BluetoothService.connectDeviceWithTrust(modelData)
                    }
                  }
                }
              }

              // Fallback if nothing available
              Column {
                width: parent.width
                spacing: Style.marginMedium * scaling
                visible: {
                  if (!BluetoothService.adapter || !BluetoothService.adapter.discovering || !Bluetooth.devices)
                    return false

                  var availableCount = Bluetooth.devices.values.filter(dev => {
                                                                         return dev && !dev.paired && !dev.pairing
                                                                         && !dev.blocked
                                                                         && (dev.signalStrength === undefined
                                                                             || dev.signalStrength > 0)
                                                                       }).length
                  return availableCount === 0
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.marginMedium * scaling

                  NText {
                    text: "sync"
                    font.family: "Material Symbols Outlined"
                    font.pointSize: Style.fontSizeXLL * 1.5 * scaling
                    color: Color.mPrimary
                    anchors.verticalCenter: parent.verticalCenter

                    RotationAnimation on rotation {
                      running: true
                      loops: Animation.Infinite
                      from: 0
                      to: 360
                      duration: 2000
                    }
                  }

                  NText {
                    text: "Scanning for devices..."
                    font.pointSize: Style.fontSizeLarge * scaling
                    color: Color.mOnSurface
                    font.weight: Style.fontWeightMedium
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                NText {
                  text: "Make sure your device is in pairing mode"
                  font.pointSize: Style.fontSizeMedium * scaling
                  color: Color.mOnSurfaceVariant
                  anchors.horizontalCenter: parent.horizontalCenter
                }
              }

              NText {
                text: "No devices found. Put your device in pairing mode and click Start Scanning."
                font.pointSize: Style.fontSizeMedium * scaling
                color: Color.mOnSurfaceVariant
                visible: {
                  if (!BluetoothService.adapter || !Bluetooth.devices)
                    return true

                  var availableCount = Bluetooth.devices.values.filter(dev => {
                                                                         return dev && !dev.paired && !dev.pairing
                                                                         && !dev.blocked
                                                                         && (dev.signalStrength === undefined
                                                                             || dev.signalStrength > 0)
                                                                       }).length
                  return availableCount === 0 && !BluetoothService.adapter.discovering
                }
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
          // This item takes up all the remaining vertical space.
          Item {
            Layout.fillHeight: true
          }
        }
      }
    }
  }
}
