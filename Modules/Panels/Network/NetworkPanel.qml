import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../Settings/Tabs/Connections" as WifiPrefs
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(500 * Style.uiScaleRatio)

  // Info panel collapsed by default, view mode persisted in settings
  // Ethernet details UI state (mirrors Wi-Fi info behavior)
  property bool ethernetInfoExpanded: false
  property bool ethernetDetailsGrid: (Settings.data.network.wifiDetailsViewMode === "grid")
  property int ipVersion: 4

  // Unified panel view mode: "wifi" | "ethernet" | "vpn" (persisted)
  property string panelViewMode: "wifi"
  property bool panelViewPersistEnabled: false

  onPanelViewModeChanged: {
    if (panelViewPersistEnabled) {
      Settings.data.network.networkPanelView = panelViewMode;
    }

    if (panelViewMode === "wifi") {
      ethernetInfoExpanded = false;
      if (NetworkService.wifiEnabled && !NetworkService.scanningActive) {
        NetworkService.scan();
        NetworkService.refreshActiveWifiDetails();
      }
    } else if (panelViewMode === "ethernet") {
      if (NetworkService.ethernetConnected) {
        NetworkService.refreshActiveEthernetDetails();
      }
    } else if (panelViewMode === "vpn") {
      VPNService.refresh();
    }
  }

  readonly property bool effectivelyVisible: root.visible && Window.window && Window.window.visible

  onEffectivelyVisibleChanged: {
    if (effectivelyVisible) {
      SystemStatService.registerComponent("network-panel");
      if (NetworkService.wifiEnabled && !NetworkService.scanningActive) {
        NetworkService.scan();
        NetworkService.refreshActiveWifiDetails();
      }
      if (NetworkService.ethernetConnected) {
        NetworkService.refreshActiveEthernetDetails();
      }
      VPNService.refresh();
    } else {
      SystemStatService.unregisterComponent("network-panel");
    }
  }

  onOpened: {
    // Default opening logic:
    // - If Wi-Fi is actively connected, open Wi-Fi first
    // - Otherwise always open Ethernet first
    // VPN is manual-only and should not be auto-selected
    if (NetworkService.wifiConnected) {
      panelViewMode = "wifi";
    } else {
      panelViewMode = "ethernet";
    }

    panelViewPersistEnabled = true;
  }

  panelContent: Rectangle {
    color: "transparent"

    property real contentPreferredHeight: Math.min(root.preferredHeight, mainColumn.implicitHeight + Style.margin2L)

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: header.implicitHeight + Style.margin2M

        ColumnLayout {
          id: header
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          RowLayout {
            NIcon {
              id: modeIcon
              icon: panelViewMode === "wifi"
                    ? (NetworkService.wifiEnabled ? "wifi" : "wifi-off")
                    : panelViewMode === "ethernet"
                      ? (NetworkService.ethernetAvailable ? "ethernet" : "ethernet-off")
                      : (VPNService.hasActiveConnection ? "shield-lock" : "shield")
              pointSize: Style.fontSizeXXL
              color: {
                if (panelViewMode === "wifi") {
                  return NetworkService.wifiEnabled ? Color.mPrimary : Color.mOnSurfaceVariant;
                } else if (panelViewMode === "ethernet") {
                  return NetworkService.ethernetConnected ? Color.mPrimary : Color.mOnSurfaceVariant;
                } else {
                  return VPNService.hasActiveConnection ? Color.mPrimary : Color.mOnSurfaceVariant;
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                onClicked: {
                  if (panelViewMode === "wifi") {
                    panelViewMode = "ethernet";
                  } else if (panelViewMode === "ethernet") {
                    panelViewMode = "vpn";
                  } else {
                    panelViewMode = NetworkService.wifiAvailable ? "wifi" : "ethernet";
                  }
                }

                onEntered: TooltipService.show(
                             parent,
                             panelViewMode === "wifi"
                             ? I18n.tr("common.wifi")
                             : panelViewMode === "ethernet"
                               ? I18n.tr("common.ethernet")
                               : "VPN"
                           )
                onExited: TooltipService.hide()
              }
            }

            NLabel {
              label: panelViewMode === "wifi"
                     ? I18n.tr("common.wifi")
                     : panelViewMode === "ethernet"
                       ? I18n.tr("common.ethernet")
                       : "VPN"
              Layout.fillWidth: true
            }

            NToggle {
              id: wifiSwitch
              visible: panelViewMode === "wifi"
              checked: NetworkService.wifiEnabled
              enabled: !NetworkService.airplaneModeEnabled && NetworkService.wifiAvailable
              onToggled: checked => NetworkService.setWifiEnabled(checked)
              baseSize: Style.baseWidgetSize * 0.7
            }

            NIconButton {
              icon: "settings"
              tooltipText: I18n.tr("tooltips.open-settings")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: SettingsPanelService.openToTab(SettingsPanel.Tab.Connections, 0, screen)
            }

            NIconButton {
              icon: "close"
              tooltipText: I18n.tr("common.close")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.close()
            }
          }

          NTabBar {
            id: modeTabBar
            visible: true
            margins: Style.marginS
            Layout.fillWidth: true
            spacing: Style.marginM
            distributeEvenly: true
            currentIndex: root.panelViewMode === "wifi" ? 0 : root.panelViewMode === "ethernet" ? 1 : 2

            onCurrentIndexChanged: {
              root.panelViewMode = currentIndex === 0 ? "wifi" : currentIndex === 1 ? "ethernet" : "vpn";
            }

            NTabButton {
              text: I18n.tr("common.wifi")
              tabIndex: 0
              checked: modeTabBar.currentIndex === 0
            }

            NTabButton {
              text: I18n.tr("common.ethernet")
              tabIndex: 1
              checked: modeTabBar.currentIndex === 1
            }

            NTabButton {
              text: "VPN"
              tabIndex: 2
              checked: modeTabBar.currentIndex === 2
            }
          }
        }
      }

      ColumnLayout {
        id: wifiSectionContainer
        visible: true
        Layout.fillWidth: true
        spacing: Style.marginM

        Rectangle {
          visible: panelViewMode === "wifi" && NetworkService.lastError.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: errorRow.implicitHeight + Style.margin2M
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

        Rectangle {
          visible: panelViewMode === "vpn" && VPNService.lastError.length > 0
          Layout.fillWidth: true
          Layout.preferredHeight: vpnErrorRow.implicitHeight + Style.margin2M
          color: Qt.alpha(Color.mError, 0.1)
          radius: Style.radiusS
          border.width: Style.borderS
          border.color: Color.mError

          RowLayout {
            id: vpnErrorRow
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginS

            NIcon {
              icon: "warning"
              pointSize: Style.fontSizeL
              color: Color.mError
            }

            NText {
              text: VPNService.lastError
              color: Color.mError
              pointSize: Style.fontSizeS
              wrapMode: Text.Wrap
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "close"
              baseSize: Style.baseWidgetSize * 0.6
              onClicked: VPNService.lastError = ""
            }
          }
        }

        NScrollView {
          id: contentScroll
          Layout.fillWidth: true
          Layout.fillHeight: true
          horizontalPolicy: ScrollBar.AlwaysOff
          verticalPolicy: ScrollBar.AsNeeded
          reserveScrollbarSpace: false
          gradientColor: Color.mSurface

          ColumnLayout {
            id: contentColumn
            width: contentScroll.availableWidth
            spacing: Style.marginM

            NBox {
              id: disabledBox
              visible: panelViewMode === "wifi" && !NetworkService.wifiEnabled
              Layout.fillWidth: true
              Layout.preferredHeight: disabledColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: disabledColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginL

                Item { Layout.fillHeight: true }

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

                Item { Layout.fillHeight: true }
              }
            }

            NBox {
              id: scanningBox
              visible: panelViewMode === "wifi" && NetworkService.wifiEnabled && Object.keys(NetworkService.networks).length === 0 && NetworkService.scanningActive
              Layout.fillWidth: true
              Layout.preferredHeight: scanningColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: scanningColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginL

                Item { Layout.fillHeight: true }

                NBusyIndicator {
                  running: visible && root.effectivelyVisible
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

                Item { Layout.fillHeight: true }
              }
            }

            NBox {
              id: emptyBox
              visible: panelViewMode === "wifi" && NetworkService.wifiEnabled && Object.keys(NetworkService.networks).length === 0 && !NetworkService.scanningActive
              Layout.fillWidth: true
              Layout.preferredHeight: emptyColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: emptyColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginL

                Item { Layout.fillHeight: true }

                NIcon {
                  icon: "wifi-question"
                  pointSize: 48
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: I18n.tr("wifi.panel.no-networks")
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                Item { Layout.fillHeight: true }
              }
            }

            ColumnLayout {
              id: networksList
              visible: panelViewMode === "wifi" && NetworkService.wifiEnabled && Object.keys(NetworkService.networks).length > 0
              width: parent.width
              spacing: Style.marginM

              WifiPrefs.WifiSubTab {
                showOnlyLists: true
              }
            }

            NBox {
              id: ethernetSection
              visible: panelViewMode === "ethernet"
              Layout.fillWidth: true
              Layout.preferredHeight: ethernetColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: ethernetColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                NLabel {
                  label: I18n.tr("wifi.panel.available-interfaces")
                  visible: (NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0)
                }

                ColumnLayout {
                  id: emptyEthColumn
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                  Layout.preferredHeight: emptyEthColumn.implicitHeight + Style.margin2M
                  visible: !(NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0)
                  spacing: Style.marginL

                  Item { Layout.fillHeight: true }

                  NIcon {
                    icon: "ethernet-off"
                    pointSize: 48
                    color: Color.mOnSurfaceVariant
                    Layout.alignment: Qt.AlignHCenter
                  }

                  NText {
                    text: I18n.tr("wifi.panel.no-ethernet-devices")
                    pointSize: Style.fontSizeL
                    color: Color.mOnSurfaceVariant
                    Layout.alignment: Qt.AlignHCenter
                  }

                  Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                  id: ethIfacesList
                  visible: NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0
                  width: parent.width
                  spacing: Style.marginXS

                  Repeater {
                    model: NetworkService.ethernetInterfaces || []

                    delegate: NBox {
                      id: ethItem

                      function getContentColors(defaultColors = [Color.mSurface, Color.mOnSurface]) {
                        if (modelData.connected) {
                          return [Color.mPrimary, Color.mOnPrimary];
                        }
                        return defaultColors;
                      }

                      Layout.fillWidth: true
                      Layout.leftMargin: Style.marginXS
                      Layout.rightMargin: Style.marginXS
                      implicitHeight: ethItemColumn.implicitHeight + Style.margin2M
                      radius: Style.radiusM
                      forceOpaque: true
                      color: ethItem.getContentColors()[0]

                      ColumnLayout {
                        id: ethItemColumn
                        width: parent.width - Style.margin2M
                        x: Style.marginM
                        y: Style.marginM
                        spacing: Style.marginS

                        RowLayout {
                          id: ethHeaderRow
                          Layout.fillWidth: true
                          spacing: Style.marginS

                          NIcon {
                            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                            horizontalAlignment: Text.AlignLeft
                            icon: NetworkService.getIcon(true)
                            pointSize: Style.fontSizeXXL
                            color: ethItem.getContentColors()[1]
                          }

                          ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            NText {
                              text: modelData.connectionName || modelData.ifname
                              pointSize: Style.fontSizeM
                              font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
                              color: ethItem.getContentColors()[1]
                              elide: Text.ElideRight
                              Layout.fillWidth: true
                            }

                            RowLayout {
                              spacing: Style.marginXS

                              NText {
                                text: {
                                  if (modelData.connected) {
                                    switch (NetworkService.networkConnectivity) {
                                    case "full":
                                      return I18n.tr("common.connected");
                                    case "limited":
                                    case "unknown":
                                      return I18n.tr("wifi.panel.internet-limited");
                                    case "portal":
                                      return I18n.tr("wifi.panel.action-required");
                                    default:
                                      return NetworkService.networkConnectivity;
                                    }
                                  }
                                  return I18n.tr("common.disconnected");
                                }
                                pointSize: Style.fontSizeXXS
                                color: Qt.alpha(ethItem.getContentColors()[1], Style.opacityHeavy)
                              }

                              RowLayout {
                                visible: (modelData.connected && NetworkService.networkConnectivity === "full") && (SystemStatService.rxSpeed > 0 || SystemStatService.txSpeed > 0)
                                spacing: 2
                                Layout.leftMargin: Style.marginXS
                                Layout.fillWidth: false

                                NIcon {
                                  visible: SystemStatService.rxSpeed > 0
                                  icon: "arrow-down"
                                  pointSize: Style.fontSizeXXS
                                  color: Qt.alpha(ethItem.getContentColors()[1], Style.opacityHeavy)
                                }

                                NText {
                                  visible: SystemStatService.rxSpeed > 0
                                  text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
                                  pointSize: Style.fontSizeXXS
                                  color: Qt.alpha(ethItem.getContentColors()[1], Style.opacityHeavy)
                                  elide: Text.ElideNone
                                }

                                Item {
                                  visible: SystemStatService.rxSpeed > 0 && SystemStatService.txSpeed > 0
                                  width: Style.marginXS
                                  height: 1
                                }

                                NIcon {
                                  visible: SystemStatService.txSpeed > 0
                                  icon: "arrow-up"
                                  pointSize: Style.fontSizeXXS
                                  color: Qt.alpha(ethItem.getContentColors()[1], Style.opacityHeavy)
                                }

                                NText {
                                  visible: SystemStatService.txSpeed > 0
                                  text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
                                  pointSize: Style.fontSizeXXS
                                  color: Qt.alpha(ethItem.getContentColors()[1], Style.opacityHeavy)
                                  elide: Text.ElideNone
                                }
                              }
                            }
                          }

                          NIconButton {
                            icon: "info"
                            tooltipText: I18n.tr("common.info")
                            baseSize: Style.baseWidgetSize * 0.75
                            colorBg: Color.mSurfaceVariant
                            colorFg: Color.mOnSurface
                            colorBorder: "transparent"
                            colorBorderHover: "transparent"
                            enabled: true
                            visible: NetworkService.ethernetConnected

                            onClicked: {
                              if (NetworkService.activeEthernetIf === modelData.ifname && ethernetInfoExpanded) {
                                ethernetInfoExpanded = false;
                                return;
                              }
                              if (NetworkService.activeEthernetIf !== modelData.ifname) {
                                NetworkService.activeEthernetIf = modelData.ifname;
                                NetworkService.activeEthernetDetailsTimestamp = 0;
                              }
                              ethernetInfoExpanded = true;
                              NetworkService.refreshActiveEthernetDetails();
                            }
                          }
                        }

                        TapHandler {
                          target: ethHeaderRow
                          onTapped: {
                            if (NetworkService.activeEthernetIf === modelData.ifname && ethernetInfoExpanded) {
                              ethernetInfoExpanded = false;
                              return;
                            }
                            if (NetworkService.activeEthernetIf !== modelData.ifname) {
                              NetworkService.activeEthernetIf = modelData.ifname;
                              NetworkService.activeEthernetDetailsTimestamp = 0;
                            }
                            ethernetInfoExpanded = true;
                            NetworkService.refreshActiveEthernetDetails();
                          }
                        }

                        Rectangle {
                          id: ethInfoInline
                          visible: ethernetInfoExpanded && NetworkService.activeEthernetIf === modelData.ifname
                          Layout.fillWidth: true
                          color: Color.mSurfaceVariant
                          radius: Style.radiusXS
                          border.width: Style.borderS
                          border.color: Style.boxBorderColor
                          implicitHeight: ethInfoGrid.implicitHeight + Style.margin2S
                          clip: true
                          Layout.topMargin: Style.marginXS

                          NIconButton {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Style.marginS
                            icon: ethernetDetailsGrid ? "layout-list" : "layout-grid"
                            tooltipText: ethernetDetailsGrid ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
                            baseSize: Style.baseWidgetSize * 0.65
                            onClicked: {
                              ethernetDetailsGrid = !ethernetDetailsGrid;
                              Settings.data.network.wifiDetailsViewMode = ethernetDetailsGrid ? "grid" : "list";
                            }
                            z: 1
                          }

                          GridLayout {
                            id: ethInfoGrid
                            anchors.fill: parent
                            anchors.margins: Style.marginS
                            anchors.rightMargin: Style.baseWidgetSize
                            flow: ethernetDetailsGrid ? GridLayout.TopToBottom : GridLayout.LeftToRight
                            rows: ethernetDetailsGrid ? 3 : 6
                            columns: ethernetDetailsGrid ? 2 : 1
                            columnSpacing: Style.marginM
                            rowSpacing: Style.marginXS

                            onColumnsChanged: {
                              if (ethInfoGrid.forceLayout) {
                                Qt.callLater(function () {
                                  ethInfoGrid.forceLayout();
                                });
                              }
                            }

                            RowLayout {
                              Layout.fillWidth: true
                              Layout.preferredWidth: 1
                              spacing: Style.marginXS
                              NIcon {
                                icon: "ethernet"
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.interface"))
                                  onExited: TooltipService.hide()
                                }
                              }
                              NText {
                                text: (NetworkService.activeEthernetDetails.ifname && NetworkService.activeEthernetDetails.ifname.length > 0) ? NetworkService.activeEthernetDetails.ifname : (NetworkService.activeEthernetIf || "-")
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                                elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                                maximumLineCount: ethernetDetailsGrid ? 1 : 6
                                clip: true
                                MouseArea {
                                  anchors.fill: parent
                                  enabled: ((NetworkService.activeEthernetDetails.ifname || "").length > 0) || ((NetworkService.activeEthernetIf || "").length > 0)
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    const value = (NetworkService.activeEthernetDetails.ifname && NetworkService.activeEthernetDetails.ifname.length > 0) ? NetworkService.activeEthernetDetails.ifname : (NetworkService.activeEthernetIf || "");
                                    if (value.length > 0) {
                                      Quickshell.execDetached(["wl-copy", value]);
                                      ToastService.showNotice(I18n.tr("common.ethernet"), I18n.tr("common.copied-to-clipboard"), "ethernet");
                                    }
                                  }
                                }
                              }
                            }

                            RowLayout {
                              Layout.fillWidth: true
                              Layout.preferredWidth: 1
                              spacing: Style.marginXS
                              NIcon {
                                icon: "hash"
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  onEntered: TooltipService.show(parent, I18n.tr("bluetooth.panel.device-address"))
                                  onExited: TooltipService.hide()
                                }
                              }
                              NText {
                                text: NetworkService.activeEthernetDetails.hwAddr || "-"
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                                elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                                maximumLineCount: ethernetDetailsGrid ? 1 : 6
                                clip: true
                                MouseArea {
                                  anchors.fill: parent
                                  enabled: (NetworkService.activeEthernetDetails.hwAddr || "").length > 0
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    const value = NetworkService.activeEthernetDetails.hwAddr || "";
                                    if (value.length > 0) {
                                      Quickshell.execDetached(["wl-copy", value]);
                                      ToastService.showNotice(I18n.tr("common.ethernet"), I18n.tr("common.copied-to-clipboard"), "ethernet");
                                    }
                                  }
                                }
                              }
                            }

                            RowLayout {
                              Layout.fillWidth: true
                              Layout.preferredWidth: 1
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
                                text: (NetworkService.activeEthernetDetails.speed && NetworkService.activeEthernetDetails.speed.length > 0) ? NetworkService.activeEthernetDetails.speed : "-"
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                                elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                                maximumLineCount: ethernetDetailsGrid ? 1 : 6
                                clip: true
                              }
                            }

                            RowLayout {
                              Layout.fillWidth: true
                              Layout.preferredWidth: 1
                              spacing: Style.marginXS
                              NIcon {
                                icon: "network"
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  onEntered: TooltipService.show(parent, root.ipVersion === 4 ? I18n.tr("wifi.panel.ipv4") : I18n.tr("wifi.panel.ipv6"))
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    root.ipVersion = root.ipVersion === 4 ? 6 : 4;
                                    TooltipService.show(parent, root.ipVersion === 4 ? I18n.tr("wifi.panel.ipv4") : I18n.tr("wifi.panel.ipv6"));
                                  }
                                }
                              }
                              NText {
                                text: root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.ipv4 || "-") : ((NetworkService.activeEthernetDetails.ipv6 || []).join(", ") || "-")
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                                elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                                maximumLineCount: ethernetDetailsGrid ? 1 : 6
                                clip: true
                                MouseArea {
                                  anchors.fill: parent
                                  enabled: root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.ipv4 || "").length > 0 : (NetworkService.activeEthernetDetails.ipv6 || []).length > 0
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    const value = root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.ipv4 || "") : ((NetworkService.activeEthernetDetails.ipv6 || []).join(", ") || "");
                                    if (value.length > 0) {
                                      Quickshell.execDetached(["wl-copy", value]);
                                      ToastService.showNotice(I18n.tr("common.ethernet"), I18n.tr("common.copied-to-clipboard"), "ethernet");
                                    }
                                  }
                                }
                              }
                            }

                            RowLayout {
                              Layout.fillWidth: true
                              Layout.preferredWidth: 1
                              spacing: Style.marginXS
                              NIcon {
                                icon: "world"
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  onEntered: TooltipService.show(parent, root.ipVersion === 4 ? I18n.tr("wifi.panel.dns") + " (" + I18n.tr("wifi.panel.ipv4") + ")" : I18n.tr("wifi.panel.dns") + " (" + I18n.tr("wifi.panel.ipv6") + ")")
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    root.ipVersion = root.ipVersion === 4 ? 6 : 4;
                                    TooltipService.show(parent, root.ipVersion === 4 ? I18n.tr("wifi.panel.dns") + " (" + I18n.tr("wifi.panel.ipv4") + ")" : I18n.tr("wifi.panel.dns") + " (" + I18n.tr("wifi.panel.ipv6") + ")");
                                  }
                                }
                              }
                              NText {
                                text: root.ipVersion === 4 ? ((NetworkService.activeEthernetDetails.dns4 || []).join(", ") || "-") : ((NetworkService.activeEthernetDetails.dns6 || []).join(", ") || "-")
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                                elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                                maximumLineCount: ethernetDetailsGrid ? 1 : 6
                                clip: true
                                MouseArea {
                                  anchors.fill: parent
                                  enabled: root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.dns4 || []).length > 0 : (NetworkService.activeEthernetDetails.dns6 || []).length > 0
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    const value = root.ipVersion === 4 ? ((NetworkService.activeEthernetDetails.dns4 || []).join(", ") || "") : ((NetworkService.activeEthernetDetails.dns6 || []).join(", ") || "");
                                    if (value.length > 0) {
                                      Quickshell.execDetached(["wl-copy", value]);
                                      ToastService.showNotice(I18n.tr("common.ethernet"), I18n.tr("common.copied-to-clipboard"), "ethernet");
                                    }
                                  }
                                }
                              }
                            }

                            RowLayout {
                              Layout.fillWidth: true
                              Layout.preferredWidth: 1
                              spacing: Style.marginXS
                              NIcon {
                                icon: "router"
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.alignment: Qt.AlignVCenter
                                MouseArea {
                                  anchors.fill: parent
                                  hoverEnabled: true
                                  onEntered: TooltipService.show(parent, root.ipVersion === 4 ? I18n.tr("common.gateway") + " (" + I18n.tr("wifi.panel.ipv4") + ")" : I18n.tr("common.gateway") + " (" + I18n.tr("wifi.panel.ipv6") + ")")
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    root.ipVersion = root.ipVersion === 4 ? 6 : 4;
                                    TooltipService.show(parent, root.ipVersion === 4 ? I18n.tr("common.gateway") + " (" + I18n.tr("wifi.panel.ipv4") + ")" : I18n.tr("common.gateway") + " (" + I18n.tr("wifi.panel.ipv6") + ")");
                                  }
                                }
                              }
                              NText {
                                text: root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.gateway4 || "-") : ((NetworkService.activeEthernetDetails.gateway6 || []).join(", ") || "-")
                                pointSize: Style.fontSizeXS
                                color: Color.mOnSurface
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                                elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                                maximumLineCount: ethernetDetailsGrid ? 1 : 6
                                clip: true
                                MouseArea {
                                  anchors.fill: parent
                                  enabled: root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.gateway4 || "").length > 0 : (NetworkService.activeEthernetDetails.gateway6 || []).length > 0
                                  hoverEnabled: true
                                  cursorShape: Qt.PointingHandCursor
                                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                                  onExited: TooltipService.hide()
                                  onClicked: {
                                    const value = root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.gateway4 || "") : ((NetworkService.activeEthernetDetails.gateway6 || []).join(", ") || "");
                                    if (value.length > 0) {
                                      Quickshell.execDetached(["wl-copy", value]);
                                      ToastService.showNotice(I18n.tr("common.ethernet"), I18n.tr("common.copied-to-clipboard"), "ethernet");
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            NBox {
              id: vpnSection
              visible: panelViewMode === "vpn"
              Layout.fillWidth: true
              Layout.preferredHeight: vpnColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: vpnColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                ColumnLayout {
                  visible: Object.keys(VPNService.connections).length === 0
                  Layout.fillWidth: true
                  spacing: Style.marginL

                  NIcon {
                    icon: "shield"
                    pointSize: 48
                    color: Color.mOnSurfaceVariant
                    Layout.alignment: Qt.AlignHCenter
                  }

                  NText {
                    text: "No VPN connections"
                    pointSize: Style.fontSizeL
                    color: Color.mOnSurfaceVariant
                    Layout.alignment: Qt.AlignHCenter
                  }
                }

                ColumnLayout {
                  visible: VPNService.activeConnections.length > 0
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NLabel {
                    label: I18n.tr("common.connected")
                  }

                  Repeater {
                    model: VPNService.activeConnections

                    delegate: NBox {
                      id: activeVpnItem
                      Layout.fillWidth: true
                      implicitHeight: activeVpnRow.implicitHeight + Style.margin2M
                      radius: Style.radiusL
                      forceOpaque: true
                      color: Qt.alpha(Color.mPrimary, 0.18)

                      RowLayout {
                        id: activeVpnRow
                        anchors.fill: parent
                        anchors.margins: Style.marginM
                        spacing: Style.marginM

                        NIcon {
                          icon: "shield-lock"
                          pointSize: Style.fontSizeXXL
                          color: Color.mPrimary
                          Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 2

                          NText {
                            text: modelData.name
                            pointSize: Style.fontSizeL
                            font.weight: Style.fontWeightBold
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                          }

                          RowLayout {
                            spacing: Style.marginS

                            NText {
                              text: "VPN"
                              pointSize: Style.fontSizeS
                              color: Color.mOnSurfaceVariant
                            }

                            Rectangle {
                              radius: 999
                              color: Color.mPrimary
                              implicitHeight: connectedBadgeText.implicitHeight + Style.marginS
                              implicitWidth: connectedBadgeText.implicitWidth + Style.marginM

                              NText {
                                id: connectedBadgeText
                                anchors.centerIn: parent
                                text: I18n.tr("common.connected")
                                pointSize: Style.fontSizeS
                                color: Color.mOnPrimary
                              }
                            }
                          }
                        }

                        RowLayout {
                          spacing: Style.marginS
                          Layout.alignment: Qt.AlignVCenter

                          NBusyIndicator {
                            visible: VPNService.disconnectingUuid === modelData.uuid
                            running: visible
                            color: Color.mPrimary
                            size: Math.round(Style.baseWidgetSize * 0.55)
                          }

                          Rectangle {
                            id: disconnectButton
                            radius: 999
                            implicitHeight: disconnectLabel.implicitHeight + Style.marginM
                            implicitWidth: disconnectLabel.implicitWidth + Style.marginL
                            color: "transparent"
                            border.width: Style.borderM
                            border.color: Color.mError
                            opacity: (!VPNService.connecting && !VPNService.disconnecting) ? 1.0 : 0.5

                            NText {
                              id: disconnectLabel
                              anchors.centerIn: parent
                              text: VPNService.disconnectingUuid === modelData.uuid
                                    ? I18n.tr("common.disconnecting")
                                    : I18n.tr("common.disconnect")
                              pointSize: Style.fontSizeM
                              color: Color.mError
                              font.weight: Style.fontWeightBold
                            }

                            MouseArea {
                              anchors.fill: parent
                              enabled: !VPNService.connecting && !VPNService.disconnecting
                              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                              onClicked: VPNService.disconnect(modelData.uuid)
                            }
                          }
                        }
                      }
                    }
                  }
                }

                ColumnLayout {
                  visible: VPNService.inactiveConnections.length > 0
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NLabel {
                    label: I18n.tr("common.disconnected")
                  }

                  Repeater {
                    model: VPNService.inactiveConnections

                    delegate: NBox {
                      id: inactiveVpnItem
                      Layout.fillWidth: true
                      implicitHeight: inactiveVpnRow.implicitHeight + Style.margin2M
                      radius: Style.radiusL
                      forceOpaque: true
                      color: Color.mSurface

                      RowLayout {
                        id: inactiveVpnRow
                        anchors.fill: parent
                        anchors.margins: Style.marginM
                        spacing: Style.marginM

                        NIcon {
                          icon: "shield"
                          pointSize: Style.fontSizeXXL
                          color: Color.mOnSurface
                          Layout.alignment: Qt.AlignVCenter
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 2

                          NText {
                            text: modelData.name
                            pointSize: Style.fontSizeL
                            font.weight: Style.fontWeightBold
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                          }

                          NText {
                            text: "VPN"
                            pointSize: Style.fontSizeS
                            color: Color.mOnSurfaceVariant
                          }
                        }

                        RowLayout {
                          spacing: Style.marginS
                          Layout.alignment: Qt.AlignVCenter

                          NBusyIndicator {
                            visible: VPNService.connectingUuid === modelData.uuid
                            running: visible
                            color: Color.mPrimary
                            size: Math.round(Style.baseWidgetSize * 0.55)
                          }

                          Rectangle {
                            id: connectButton
                            radius: 999
                            implicitHeight: connectLabel.implicitHeight + Style.marginM
                            implicitWidth: connectLabel.implicitWidth + Style.marginL
                            color: "transparent"
                            border.width: Style.borderM
                            border.color: Color.mPrimary
                            opacity: (!VPNService.connecting && !VPNService.disconnecting) ? 1.0 : 0.5

                            NText {
                              id: connectLabel
                              anchors.centerIn: parent
                              text: VPNService.connectingUuid === modelData.uuid
                                    ? I18n.tr("common.connecting")
                                    : I18n.tr("common.connect")
                              pointSize: Style.fontSizeM
                              color: Color.mPrimary
                              font.weight: Style.fontWeightBold
                            }

                            MouseArea {
                              anchors.fill: parent
                              enabled: !VPNService.connecting && !VPNService.disconnecting
                              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                              onClicked: VPNService.connect(modelData.uuid)
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}