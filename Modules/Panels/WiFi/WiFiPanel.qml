import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Networking
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(400 * Style.uiScaleRatio)
  preferredHeight: Math.round(500 * Style.uiScaleRatio)

  property string passwordSsid: ""
  property string passwordInput: ""
  property string expandedSsid: ""

  onOpened: NetworkService.scan()

  panelContent: Rectangle {
    color: Color.transparent

    property real contentPreferredHeight: Math.min(preferredHeight, Math.max(280 * Style.uiScaleRatio, mainColumn.implicitHeight + Style.marginL * 2))

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Header
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: headerRow.implicitHeight + Style.marginM * 2

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: Settings.data.network.wifiEnabled ? "wifi" : "wifi-off"
            pointSize: Style.fontSizeXXL
            color: Settings.data.network.wifiEnabled ? Color.mPrimary : Color.mOnSurfaceVariant
          }

          NText {
            text: I18n.tr("wifi.panel.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NToggle {
            id: wifiSwitch
            checked: Settings.data.network.wifiEnabled
            onToggled: checked => NetworkService.setWifiEnabled(checked)
            baseSize: Style.baseWidgetSize * 0.65
          }

          NIconButton {
            icon: "refresh"
            tooltipText: I18n.tr("tooltips.refresh")
            baseSize: Style.baseWidgetSize * 0.8
            enabled: Settings.data.network.wifiEnabled && !NetworkService.scanning
            onClicked: NetworkService.scan()
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("tooltips.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: root.close()
          }
        }
      }
      // Error message
      Rectangle {
        visible: NetworkService.lastError.length > 0
        Layout.fillWidth: true
        Layout.preferredHeight: errorRow.implicitHeight + (Style.marginM * 2)
        color: Qt.alpha(Color.mError, 0.1)
        radius: Style.radiusS
        border.width: Style.borderS
        border.color: Color.mError

        RowLayout {
          id: errorRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NIcon {
            icon: "warning"
            pointSize: Style.fontSizeL
            color: Color.mError
          }

          NText {
            text: NetworkService.lastError
            color: Color.mError
            pointSize: Style.fontSizeS
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "close"
            baseSize: Style.baseWidgetSize * 0.6
            onClicked: NetworkService.lastError = ""
          }
        }
      }

      // Main content area
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // WiFi disabled state
        ColumnLayout {
          visible: !Settings.data.network.wifiEnabled
          anchors.fill: parent
          anchors.margins: Style.marginM

          Item {
            Layout.fillHeight: true
          }

          NIcon {
            icon: "wifi-off"
            pointSize: 48
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: I18n.tr("wifi.panel.disabled")
            pointSize: Style.fontSizeL
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: I18n.tr("wifi.panel.enable-message")
            pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          Item {
            Layout.fillHeight: true
          }
        }

        // Scanning state
        ColumnLayout {
          visible: Settings.data.network.wifiEnabled && NetworkService.scanning && Object.keys(NetworkService.networks).length === 0
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginL

          Item {
            Layout.fillHeight: true
          }

          NBusyIndicator {
            running: true
            color: Color.mPrimary
            size: Style.baseWidgetSize
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: I18n.tr("wifi.panel.searching")
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          Item {
            Layout.fillHeight: true
          }
        }

        // Networks list container
        NScrollView {
          visible: Settings.data.network.wifiEnabled && (!NetworkService.scanning || Object.keys(NetworkService.networks).length > 0)
          anchors.fill: parent
          anchors.margins: Style.marginM
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          clip: true

          ColumnLayout {
            width: parent.width
            spacing: Style.marginM

            // Network list
            Repeater {
              model: {
                if (!Settings.data.network.wifiEnabled)
                  return []

                const nets = Object.values(NetworkService.networks)
                return nets.sort((a, b) => {
                                   if (a.connected !== b.connected)
                                   return b.connected - a.connected
                                   return b.signal - a.signal
                                 })
              }

              Rectangle {
                Layout.fillWidth: true
                implicitHeight: netColumn.implicitHeight + (Style.marginM * 2)
                radius: Style.radiusM

                // Add opacity for operations in progress
                opacity: (NetworkService.disconnectingFrom === modelData.ssid || NetworkService.forgettingNetwork === modelData.ssid) ? 0.6 : 1.0

                color: modelData.connected ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.05) : Color.mSurface
                border.width: Style.borderS
                border.color: modelData.connected ? Color.mPrimary : Color.mOutline

                // Smooth opacity animation
                Behavior on opacity {
                  NumberAnimation {
                    duration: Style.animationNormal
                  }
                }

                ColumnLayout {
                  id: netColumn
                  width: parent.width - (Style.marginM * 2)
                  x: Style.marginM
                  y: Style.marginM
                  spacing: Style.marginS

                  // Main row
                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginS

                    NIcon {
                      icon: NetworkService.signalIcon(modelData.signal, modelData.connected)
                      pointSize: Style.fontSizeXXL
                      color: modelData.connected ? Color.mPrimary : Color.mOnSurface
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 2

                      NText {
                        text: modelData.ssid
                        pointSize: Style.fontSizeM
                        font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
                        color: Color.mOnSurface
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                      }

                      RowLayout {
                        spacing: Style.marginXS

                        NText {
                          text: I18n.tr("system.signal-strength", {
                                          "signal": modelData.signal
                                        })
                          pointSize: Style.fontSizeXXS
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: "•"
                          pointSize: Style.fontSizeXXS
                          color: Color.mOnSurfaceVariant
                        }

                        NText {
                          text: NetworkService.isSecured(modelData.security) ? modelData.security : "Open"
                          pointSize: Style.fontSizeXXS
                          color: Color.mOnSurfaceVariant
                        }

                        Item {
                          Layout.preferredWidth: Style.marginXXS
                        }

                        // Update the status badges area (around line 237)
                        Rectangle {
                          visible: modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid
                          color: Color.mPrimary
                          radius: height * 0.5
                          width: connectedText.implicitWidth + (Style.marginS * 2)
                          height: connectedText.implicitHeight + (Style.marginXXS * 2)

                          NText {
                            id: connectedText
                            anchors.centerIn: parent
                            text: I18n.tr("wifi.panel.connected")
                            pointSize: Style.fontSizeXXS
                            color: Color.mOnPrimary
                          }
                        }

                        Rectangle {
                          visible: NetworkService.disconnectingFrom === modelData.ssid
                          color: Color.mError
                          radius: height * 0.5
                          width: disconnectingText.implicitWidth + (Style.marginS * 2)
                          height: disconnectingText.implicitHeight + (Style.marginXXS * 2)

                          NText {
                            id: disconnectingText
                            anchors.centerIn: parent
                            text: I18n.tr("wifi.panel.disconnecting")
                            pointSize: Style.fontSizeXXS
                            color: Color.mOnPrimary
                          }
                        }

                        Rectangle {
                          visible: NetworkService.forgettingNetwork === modelData.ssid
                          color: Color.mError
                          radius: height * 0.5
                          width: forgettingText.implicitWidth + (Style.marginS * 2)
                          height: forgettingText.implicitHeight + (Style.marginXXS * 2)

                          NText {
                            id: forgettingText
                            anchors.centerIn: parent
                            text: I18n.tr("wifi.panel.forgetting")
                            pointSize: Style.fontSizeXXS
                            color: Color.mOnPrimary
                          }
                        }

                        Rectangle {
                          visible: modelData.cached && !modelData.connected && NetworkService.forgettingNetwork !== modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid
                          color: Color.transparent
                          border.color: Color.mOutline
                          border.width: Style.borderS
                          radius: height * 0.5
                          width: savedText.implicitWidth + (Style.marginS * 2)
                          height: savedText.implicitHeight + (Style.marginXXS * 2)

                          NText {
                            id: savedText
                            anchors.centerIn: parent
                            text: I18n.tr("wifi.panel.saved")
                            pointSize: Style.fontSizeXXS
                            color: Color.mOnSurfaceVariant
                          }
                        }
                      }
                    }

                    // Action area
                    RowLayout {
                      spacing: Style.marginS

                      NBusyIndicator {
                        visible: NetworkService.connectingTo === modelData.ssid || NetworkService.disconnectingFrom === modelData.ssid || NetworkService.forgettingNetwork === modelData.ssid
                        running: visible
                        color: Color.mPrimary
                        size: Style.baseWidgetSize * 0.5
                      }

                      NIconButton {
                        visible: (modelData.existing || modelData.cached) && !modelData.connected && NetworkService.connectingTo !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid
                        icon: "trash"
                        tooltipText: I18n.tr("tooltips.forget-network")
                        baseSize: Style.baseWidgetSize * 0.8
                        onClicked: expandedSsid = expandedSsid === modelData.ssid ? "" : modelData.ssid
                      }

                      NButton {
                        visible: !modelData.connected && NetworkService.connectingTo !== modelData.ssid && passwordSsid !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid
                        text: {
                          if (modelData.existing || modelData.cached)
                            return I18n.tr("wifi.panel.connect")
                          if (!NetworkService.isSecured(modelData.security))
                            return I18n.tr("wifi.panel.connect")
                          return I18n.tr("wifi.panel.password")
                        }
                        outlined: !hovered
                        fontSize: Style.fontSizeXS
                        enabled: !NetworkService.connecting
                        onClicked: {
                          if (modelData.existing || modelData.cached || !NetworkService.isSecured(modelData.security)) {
                            NetworkService.connect(modelData.ssid)
                          } else {
                            passwordSsid = modelData.ssid
                            passwordInput = ""
                            expandedSsid = ""
                          }
                        }
                      }

                      NButton {
                        visible: modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid
                        text: I18n.tr("wifi.panel.disconnect")
                        outlined: !hovered
                        fontSize: Style.fontSizeXS
                        backgroundColor: Color.mError
                        onClicked: NetworkService.disconnect(modelData.ssid)
                      }
                    }
                  }

                  // Password input
                  Rectangle {
                    visible: passwordSsid === modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid
                    Layout.fillWidth: true
                    height: passwordRow.implicitHeight + Style.marginS * 2
                    color: Color.mSurfaceVariant
                    border.color: Color.mOutline
                    border.width: Style.borderS
                    radius: Style.radiusS

                    RowLayout {
                      id: passwordRow
                      anchors.fill: parent
                      anchors.margins: Style.marginS
                      spacing: Style.marginM

                      Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Style.radiusXS
                        color: Color.mSurface
                        border.color: pwdInput.activeFocus ? Color.mSecondary : Color.mOutline
                        border.width: Style.borderS

                        TextInput {
                          id: pwdInput
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          anchors.margins: Style.marginS
                          text: passwordInput
                          font.family: Settings.data.ui.fontFixed
                          font.pointSize: Style.fontSizeS
                          color: Color.mOnSurface
                          echoMode: TextInput.Password
                          selectByMouse: true
                          focus: visible
                          passwordCharacter: "●"
                          onTextChanged: passwordInput = text
                          onVisibleChanged: if (visible)
                                              forceActiveFocus()
                          onAccepted: {
                            if (text && !NetworkService.connecting) {
                              NetworkService.connect(passwordSsid, text)
                              passwordSsid = ""
                              passwordInput = ""
                            }
                          }

                          NText {
                            visible: parent.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("wifi.panel.enter-password")
                            color: Color.mOnSurfaceVariant
                            pointSize: Style.fontSizeS
                          }
                        }
                      }

                      NButton {
                        text: I18n.tr("wifi.panel.connect")
                        fontSize: Style.fontSizeXXS
                        enabled: passwordInput.length > 0 && !NetworkService.connecting
                        outlined: true
                        onClicked: {
                          NetworkService.connect(passwordSsid, passwordInput)
                          passwordSsid = ""
                          passwordInput = ""
                        }
                      }

                      NIconButton {
                        icon: "close"
                        baseSize: Style.baseWidgetSize * 0.8
                        onClicked: {
                          passwordSsid = ""
                          passwordInput = ""
                        }
                      }
                    }
                  }

                  // Forget network
                  Rectangle {
                    visible: expandedSsid === modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid
                    Layout.fillWidth: true
                    height: forgetRow.implicitHeight + Style.marginS * 2
                    color: Color.mSurfaceVariant
                    radius: Style.radiusS
                    border.width: Style.borderS
                    border.color: Color.mOutline

                    RowLayout {
                      id: forgetRow
                      anchors.fill: parent
                      anchors.margins: Style.marginS
                      spacing: Style.marginM

                      RowLayout {
                        NIcon {
                          icon: "trash"
                          pointSize: Style.fontSizeL
                          color: Color.mError
                        }

                        NText {
                          text: I18n.tr("wifi.panel.forget-network")
                          pointSize: Style.fontSizeS
                          color: Color.mError
                          Layout.fillWidth: true
                        }
                      }

                      NButton {
                        id: forgetButton
                        text: I18n.tr("wifi.panel.forget")
                        fontSize: Style.fontSizeXXS
                        backgroundColor: Color.mError
                        outlined: forgetButton.hovered ? false : true
                        onClicked: {
                          NetworkService.forget(modelData.ssid)
                          expandedSsid = ""
                        }
                      }

                      NIconButton {
                        icon: "close"
                        baseSize: Style.baseWidgetSize * 0.8
                        onClicked: expandedSsid = ""
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // Empty state when no networks
        ColumnLayout {
          visible: Settings.data.network.wifiEnabled && !NetworkService.scanning && Object.keys(NetworkService.networks).length === 0
          anchors.fill: parent
          spacing: Style.marginL

          Item {
            Layout.fillHeight: true
          }

          NIcon {
            icon: "search"
            pointSize: 64
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: I18n.tr("wifi.panel.no-networks")
            pointSize: Style.fontSizeL
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          NButton {
            text: I18n.tr("wifi.panel.scan-again")
            icon: "refresh"
            Layout.alignment: Qt.AlignHCenter
            onClicked: NetworkService.scan()
          }

          Item {
            Layout.fillHeight: true
          }
        }
      }
    }
  }
}
