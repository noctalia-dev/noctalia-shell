import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NBox {
  id: root

  property string label: ""
  property var model: []
  // While a password prompt is open, we freeze the displayed model to avoid
  // frequent scan updates recreating items and clearing the TextInput.
  property var cachedModel: []
  readonly property var displayModel: (passwordSsid && passwordSsid.length > 0) ? cachedModel : model
  property string passwordSsid: ""
  property string expandedSsid: ""
  // Currently expanded info panel for a connected SSID
  property string infoSsid: ""
  // Local layout toggle for details: true = grid (2 cols), false = rows (1 col)
  // Persisted under Settings.data.ui.wifiDetailsViewMode
  property bool detailsGrid: (Settings.data && Settings.data.ui && Settings.data.ui.wifiDetailsViewMode !== undefined) ? (Settings.data.ui.wifiDetailsViewMode === "grid") : true

  signal passwordRequested(string ssid)
  signal passwordSubmitted(string ssid, string password)
  signal passwordCancelled
  signal forgetRequested(string ssid)
  signal forgetConfirmed(string ssid)
  signal forgetCancelled

  onPasswordSsidChanged: {
    if (passwordSsid && passwordSsid.length > 0) {
      // Freeze current list ordering/content while entering password
      try {
        // Deep copy to decouple from live updates
        cachedModel = JSON.parse(JSON.stringify(model));
      } catch (e) {
        // Fallback to shallow copy
        cachedModel = model.slice ? model.slice() : model;
      }
    } else {
      // Clear freeze when password box is closed
      cachedModel = [];
    }
  }

  Layout.fillWidth: true
  Layout.preferredHeight: column.implicitHeight + Style.marginM * 2
  visible: root.model.length > 0

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      visible: root.model.length > 0
      Layout.leftMargin: Style.marginS
      spacing: Style.marginS

      NText {
        text: root.label
        pointSize: Style.fontSizeS
        color: Color.mSecondary
        font.weight: Style.fontWeightBold
        Layout.fillWidth: true
      }
    }

    Repeater {
      model: root.displayModel

      Rectangle {
        id: networkItem

        Layout.fillWidth: true
        Layout.leftMargin: Style.marginXS
        Layout.rightMargin: Style.marginXS
        implicitHeight: netColumn.implicitHeight + (Style.marginM * 2)
        radius: Style.radiusM
        border.width: Style.borderS
        border.color: modelData.connected ? Color.mPrimary : Color.mOutline

        opacity: (NetworkService.disconnectingFrom === modelData.ssid || NetworkService.forgettingNetwork === modelData.ssid) ? 0.6 : 1.0

        color: modelData.connected ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.05) : Color.mSurface

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
                  text: I18n.tr("wifi.panel.signal") + ": " + modelData.signal + "%"
                  pointSize: Style.fontSizeXXS
                  color: Color.mOnSurfaceVariant
                }

                NIcon {
                  icon: "lock-off"
                  pointSize: Style.fontSizeXXS
                  color: Color.mOnSurfaceVariant
                  visible: !NetworkService.isSecured(modelData.security)
                }

                Item {
                  Layout.preferredWidth: Style.marginXXS
                }

                // Status badges
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

              // Info toggle for connected network
              NIconButton {
                visible: modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid
                icon: "info-circle"
                tooltipText: I18n.tr("wifi.panel.info")
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: {
                  if (root.infoSsid === modelData.ssid) {
                    root.infoSsid = "";
                  } else {
                    root.infoSsid = modelData.ssid;
                    NetworkService.refreshActiveWifiDetails();
                  }
                }
              }

              NIconButton {
                visible: (modelData.existing || modelData.cached) && !modelData.connected && NetworkService.connectingTo !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid
                icon: "trash"
                tooltipText: I18n.tr("tooltips.forget-network")
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: root.forgetRequested(modelData.ssid)
              }

              NButton {
                visible: !modelData.connected && NetworkService.connectingTo !== modelData.ssid && root.passwordSsid !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid
                text: {
                  if (modelData.existing || modelData.cached)
                    return I18n.tr("wifi.panel.connect");
                  if (!NetworkService.isSecured(modelData.security))
                    return I18n.tr("wifi.panel.connect");
                  return I18n.tr("wifi.panel.password");
                }
                outlined: !hovered
                fontSize: Style.fontSizeXS
                enabled: !NetworkService.connecting
                onClicked: {
                  if (modelData.existing || modelData.cached || !NetworkService.isSecured(modelData.security)) {
                    NetworkService.connect(modelData.ssid);
                  } else {
                    root.passwordRequested(modelData.ssid);
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

          // Connection info details (compact grid)
          Rectangle {
            visible: root.infoSsid === modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid
            Layout.fillWidth: true
            color: Color.mSurfaceVariant
            radius: Style.radiusS
            border.width: Style.borderS
            border.color: Color.mOutline
            implicitHeight: infoGrid.implicitHeight + Style.marginS * 2
            clip: true
            onVisibleChanged: {
              if (visible && infoGrid && infoGrid.forceLayout) {
                Qt.callLater(function () {
                  infoGrid.forceLayout();
                });
              }
            }

            // Grid/List toggle moved here to the top-right corner of the info box
            NIconButton {
              id: detailsToggle
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.marginS
              // Use Tabler layout icons; "grid" alone doesn't exist in our font
              icon: root.detailsGrid ? "layout-list" : "layout-grid"
              tooltipText: root.detailsGrid ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
              onClicked: {
                root.detailsGrid = !root.detailsGrid;
                if (Settings.data && Settings.data.ui) {
                  Settings.data.ui.wifiDetailsViewMode = root.detailsGrid ? "grid" : "list";
                }
              }
              z: 1
            }

            GridLayout {
              id: infoGrid
              anchors.fill: parent
              anchors.margins: Style.marginS
              // Layout toggle: grid (2 columns) or rows (1 column)
              columns: root.detailsGrid ? 2 : 1
              columnSpacing: Style.marginM
              rowSpacing: Style.marginXS
              // Ensure proper relayout when switching grid/list while open
              onColumnsChanged: {
                if (infoGrid.forceLayout) {
                  Qt.callLater(function () {
                    infoGrid.forceLayout();
                  });
                }
              }

              // Icons only; values have labels as tooltips on hover

              // Row 1: Security | Internet
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: NetworkService.isSecured(modelData.security) ? "lock" : "lock-open"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  // Tooltip on hover when using icons-only mode
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.security"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.isSecured(modelData.security) ? modelData.security : "Open"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 4
                  clip: true
                }
              }
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: NetworkService.internetConnectivity ? "world" : "world-off"
                  pointSize: Style.fontSizeXS
                  color: NetworkService.internetConnectivity ? Color.mOnSurface : Color.mError
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.internet"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.internetConnectivity ? I18n.tr("wifi.panel.internet-connected") : I18n.tr("wifi.panel.internet-limited")
                  pointSize: Style.fontSizeXS
                  color: NetworkService.internetConnectivity ? Color.mOnSurface : Color.mError
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 4
                  clip: true
                }
              }

              // Row 2: Link Speed | IPv4
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: "gauge"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.link-speed"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: (NetworkService.activeWifiDetails.rateShort && NetworkService.activeWifiDetails.rateShort.length > 0) ? NetworkService.activeWifiDetails.rateShort : ((NetworkService.activeWifiDetails.rate && NetworkService.activeWifiDetails.rate.length > 0) ? NetworkService.activeWifiDetails.rate : "-")
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 4
                  clip: true
                }
              }
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  // IPv4 address icon ("device-lan" doesn't exist in our font)
                  icon: "network"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.ipv4"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.activeWifiDetails.ipv4 || "-"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 4
                  clip: true
                }
              }

              // Row 3: Gateway | DNS
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: "router"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.gateway"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.activeWifiDetails.gateway4 || "-"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 4
                  clip: true
                }
              }
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                // DNS: allow wrapping when selected
                NIcon {
                  icon: "world"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.dns"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.activeWifiDetails.dns || "-"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 6
                  clip: true
                }
              }
            }
          }

          // Password input
          Rectangle {
            visible: root.passwordSsid === modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid
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
                  font.family: Settings.data.ui.fontFixed
                  font.pointSize: Style.fontSizeS
                  color: Color.mOnSurface
                  echoMode: TextInput.Password
                  selectByMouse: true
                  focus: visible
                  passwordCharacter: "●"
                  onVisibleChanged: if (visible) {
                                      // Keep any text already typed; only focus
                                      forceActiveFocus();
                                    }
                  onAccepted: {
                    if (text && !NetworkService.connecting) {
                      root.passwordSubmitted(modelData.ssid, text);
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
                enabled: pwdInput.text.length > 0 && !NetworkService.connecting
                outlined: true
                onClicked: root.passwordSubmitted(modelData.ssid, pwdInput.text)
              }

              NIconButton {
                icon: "close"
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: root.passwordCancelled()
              }
            }
          }

          // Forget network
          Rectangle {
            visible: root.expandedSsid === modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid
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
                onClicked: root.forgetConfirmed(modelData.ssid)
              }

              NIconButton {
                icon: "close"
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: root.forgetCancelled()
              }
            }
          }
        }
      }
    }
  }
}
