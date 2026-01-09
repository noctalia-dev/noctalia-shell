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
  // Persisted under Settings.data.network.wifiDetailsViewMode
  property bool detailsGrid: (Settings.data && Settings.data.ui && Settings.data.network.wifiDetailsViewMode !== undefined) ? (Settings.data.network.wifiDetailsViewMode === "grid") : true

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

      NBox {
        id: networkItem

        Layout.fillWidth: true
        Layout.leftMargin: Style.marginXS
        Layout.rightMargin: Style.marginXS
        implicitHeight: netColumn.implicitHeight + (Style.marginM * 2)

        opacity: (NetworkService.disconnectingFrom === modelData.ssid || NetworkService.forgettingNetwork === modelData.ssid) ? 0.6 : 1.0

        color: modelData.connected ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.08) : Color.mSurface

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
              color: modelData.connected ? (NetworkService.internetConnectivity ? Color.mPrimary : Color.mError) : Color.mOnSurface
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: TooltipService.show(parent, NetworkService.getSignalStrengthLabel(modelData.signal) + " (" + modelData.signal + "%)")
                onExited: TooltipService.hide()
              }
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
                  text: NetworkService.isSecured(modelData.security) ? modelData.security : "Open"
                  pointSize: Style.fontSizeXXS
                  color: Color.mOnSurfaceVariant
                }

                NIcon {
                  icon: "lock-off"
                  pointSize: Style.fontSizeXXS
                  color: Color.mOnSurfaceVariant
                  visible: !NetworkService.isSecured(modelData.security)
                }

                // Spacing

                Item {
                  Layout.preferredWidth: Style.marginXXS
                }

                // Status badges
                Rectangle {
                  visible: modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid
                  color: NetworkService.internetConnectivity ? Color.mPrimary : Color.mError
                  radius: height * 0.5
                  width: connectedText.implicitWidth + (Style.marginS * 2)
                  height: connectedText.implicitHeight + (Style.marginXXS * 2)

                  NText {
                    id: connectedText
                    anchors.centerIn: parent
                    text: {
                      switch (NetworkService.networkConnectivity) {
                      case "full":
                        return I18n.tr("common.connected");
                      case "limited":
                        return I18n.tr("wifi.panel.internet-limited");
                      case "portal":  // Where Captive Portal is detected (User intervention needed)
                        return I18n.tr("wifi.panel.action-required");
                        // I assume unknown is for connecting/disconnecting state where connectivity hasn't been determined yet (Shouldn't be visible for long enough to matter)
                        // and none is for no connectivity at all.
                        // None and Unknown will return direct output of NetworkService.networkConnectivity
                      default:
                        return NetworkService.networkConnectivity;
                      }
                    }
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
                  color: "transparent"
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
                tooltipText: I18n.tr("common.info")
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
                onClicked: root.forgetRequested(modelData.ssid)
              }

              NButton {
                visible: !modelData.connected && NetworkService.connectingTo !== modelData.ssid && root.passwordSsid !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid && NetworkService.disconnectingFrom !== modelData.ssid
                text: {
                  if (modelData.existing || modelData.cached)
                    return I18n.tr("common.connect");
                  if (!NetworkService.isSecured(modelData.security))
                    return I18n.tr("common.connect");
                  return I18n.tr("common.password");
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
                text: I18n.tr("common.disconnect")
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
                  Settings.data.network.wifiDetailsViewMode = root.detailsGrid ? "grid" : "list";
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
              // Row 1: Interface | Band
              RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: Style.marginXS
                NIcon {
                  icon: "network"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.alignment: Qt.AlignVCenter
                  // Tooltip on hover when using icons-only mode
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.interface"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.activeWifiIf || "-"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  Layout.preferredWidth: 1
                  Layout.alignment: Qt.AlignVCenter
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
                  clip: true

                  // Click-to-copy Wi‑Fi interface name
                  MouseArea {
                    anchors.fill: parent
                    enabled: (NetworkService.activeWifiIf && NetworkService.activeWifiIf.length > 0)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                    onExited: TooltipService.hide()
                    onClicked: {
                      const value = NetworkService.activeWifiIf || "";
                      if (value.length > 0) {
                        Quickshell.execDetached(["wl-copy", value]);
                        ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.bluetooth.address-copied"), "wifi");
                      }
                    }
                  }
                }
              }
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: "router"
                  pointSize: Style.fontSizeXS
                  color: NetworkService.internetConnectivity ? Color.mOnSurface : Color.mError
                  Layout.alignment: Qt.AlignVCenter
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("common.frequency"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.activeWifiDetails.band || "-"
                  pointSize: Style.fontSizeXS
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
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
                  Layout.alignment: Qt.AlignVCenter
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
                  Layout.alignment: Qt.AlignVCenter
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
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
                  Layout.alignment: Qt.AlignVCenter
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
                  Layout.alignment: Qt.AlignVCenter
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
                  clip: true

                  // Click-to-copy Wi‑Fi IPv4 address
                  MouseArea {
                    anchors.fill: parent
                    enabled: (NetworkService.activeWifiDetails.ipv4 && NetworkService.activeWifiDetails.ipv4.length > 0)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                    onExited: TooltipService.hide()
                    onClicked: {
                      const value = NetworkService.activeWifiDetails.ipv4 || "";
                      if (value.length > 0) {
                        Quickshell.execDetached(["wl-copy", value]);
                        ToastService.showNotice(I18n.tr("wifi.panel.title"), I18n.tr("toast.bluetooth.address-copied"), "wifi");
                      }
                    }
                  }
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
                  Layout.alignment: Qt.AlignVCenter
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("common.gateway"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: NetworkService.activeWifiDetails.gateway4 || "-"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
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
                  Layout.alignment: Qt.AlignVCenter
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
                  Layout.alignment: Qt.AlignVCenter
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
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
            radius: Style.iRadiusXS

            RowLayout {
              id: passwordRow
              anchors.fill: parent
              anchors.margins: Style.marginS
              spacing: Style.marginM

              Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Style.iRadiusXS
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
                text: I18n.tr("common.connect")
                fontSize: Style.fontSizeXXS
                enabled: pwdInput.text.length > 0 && !NetworkService.connecting
                outlined: true
                onClicked: root.passwordSubmitted(modelData.ssid, pwdInput.text)
              }

              NIconButton {
                icon: "close"
                baseSize: Style.baseWidgetSize
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
                baseSize: Style.baseWidgetSize
                onClicked: root.forgetCancelled()
              }
            }
          }
        }
      }
    }
  }
}
