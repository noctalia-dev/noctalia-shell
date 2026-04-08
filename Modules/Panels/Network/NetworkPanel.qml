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
  // Ethernet details UI state (mirrors Wi‑Fi info behavior)
  property bool ethernetInfoExpanded: false
  property bool ethernetDetailsGrid: (Settings.data.network.wifiDetailsViewMode === "grid")
  property int ipVersion: 4

  // Unified panel view mode: "wifi" | "ethernet" (persisted)
  property string panelViewMode: "wifi"
  property bool panelViewPersistEnabled: false

  // Whether VPN configurations exist (tab only shown when true)
  readonly property bool vpnAvailable: Object.keys(VPNService.connections).length > 0

  // If VPN configs vanish while on VPN tab, switch away
  onVpnAvailableChanged: {
    if (!vpnAvailable && panelViewMode === "vpn") {
      panelViewMode = NetworkService.wifiAvailable ? "wifi" : "ethernet";
    }
  }

  // If an adapter disappears while its tab is active, switch to the best available
  Connections {
    target: NetworkService
    function onEthernetAvailableChanged() {
      if (!NetworkService.ethernetAvailable && root.panelViewMode === "ethernet") {
        root.panelViewMode = NetworkService.wifiAvailable ? "wifi" : root.vpnAvailable ? "vpn" : "wifi";
      }
    }
    function onWifiAvailableChanged() {
      if (!NetworkService.wifiAvailable && root.panelViewMode === "wifi") {
        root.panelViewMode = NetworkService.ethernetAvailable ? "ethernet" : root.vpnAvailable ? "vpn" : "ethernet";
      }
    }
  }

  // VPN connect toast workaround: VPNService's stdout handler doesn't fire
  // for WireGuard (and possibly other types) because nmcli doesn't print
  // "successfully activated". We track the pending connect and watch
  // VPNService.connections (refreshed every 5s / 1s after connect) for
  // the UUID becoming active.
  property string _vpnPendingUuid: ""
  property string _vpnPendingName: ""

  Connections {
    target: VPNService
    function onConnectingUuidChanged() {
      if (VPNService.connectingUuid) {
        // A new connect started — capture UUID/name
        root._vpnPendingUuid = VPNService.connectingUuid;
        const conn = VPNService.connections[root._vpnPendingUuid];
        root._vpnPendingName = conn ? conn.name : "";
        _vpnConnectTimeout.restart();
      }
    }

    function onConnectingChanged() {
      if (!VPNService.connecting && root._vpnPendingUuid) {
        // connecting went false — check why:
        const conn = VPNService.connections[root._vpnPendingUuid];
        if (conn && conn.active) {
          // VPNService's stdout handler worked (OpenVPN etc.) and already
          // showed a toast + set active. Just clean up.
          root._vpnPendingUuid = "";
          root._vpnPendingName = "";
          _vpnConnectTimeout.stop();
        } else if (VPNService.lastError) {
          // stderr handler fired with an error and already showed a
          // warning toast. Clean up.
          root._vpnPendingUuid = "";
          root._vpnPendingName = "";
          _vpnConnectTimeout.stop();
        }
        // Otherwise (WireGuard success): connecting=false via empty stderr
        // handler, but active not yet set — keep pending, let
        // onConnectionsChanged pick it up after the next refresh.
      }
    }
  }

  Connections {
    target: VPNService
    function onConnectionsChanged() {
      if (!root._vpnPendingUuid) return;
      const conn = VPNService.connections[root._vpnPendingUuid];
      if (conn && conn.active) {
        ToastService.showNotice(root._vpnPendingName, I18n.tr("toast.vpn.connected", {
                                                                  "name": root._vpnPendingName
                                                                }), "shield-lock");
        root._vpnPendingUuid = "";
        root._vpnPendingName = "";
        _vpnConnectTimeout.stop();
      }
    }
  }

  Timer {
    id: _vpnConnectTimeout
    interval: 15000
    repeat: false
    onTriggered: {
      if (root._vpnPendingName) {
        ToastService.showWarning(root._vpnPendingName, I18n.tr("toast.wifi.connection-timeout"), "shield-off");
      }
      root._vpnPendingUuid = "";
      root._vpnPendingName = "";
    }
  }

  onPanelViewModeChanged: {
    // Sync tab bar (imperative – avoids declarative binding being broken by NTabButton clicks)
    let _tabIdx = 0;
    if (panelViewMode === "ethernet") _tabIdx = 1;
    else if (panelViewMode === "vpn") _tabIdx = 2;
    if (modeTabBar.currentIndex !== _tabIdx)
      modeTabBar.currentIndex = _tabIdx;

    // Persist last view (only after restored the initial value)
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
      ethernetInfoExpanded = false;
      if (NetworkService.ethernetConnected) {
        NetworkService.refreshActiveEthernetDetails();
      }
    } else if (panelViewMode === "vpn") {
      ethernetInfoExpanded = false;
      VPNService.refresh();
    }
  }

  // Effectively visible tracking
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
      if (vpnAvailable) {
        VPNService.refresh();
      }
    } else {
      SystemStatService.unregisterComponent("network-panel");
    }
  }

  onOpened: {
    if (NetworkService.wifiAvailable && NetworkService.wifiEnabled) {
      panelViewMode = "wifi";
    } else if (NetworkService.ethernetAvailable) {
      panelViewMode = "ethernet";
    } else if (vpnAvailable) {
      panelViewMode = "vpn";
    } else {
      panelViewMode = "wifi"; // fallback (shows empty/disabled state)
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

      // Header
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
              icon: {
                if (panelViewMode === "wifi") {
                  return NetworkService.wifiEnabled ? "wifi" : "wifi-off";
                } else if (panelViewMode === "ethernet") {
                  return NetworkService.ethernetAvailable ? "ethernet" : "ethernet-off";
                } else {
                  return VPNService.hasActiveConnection ? "shield-lock" : "shield";
                }
              }
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
                    if (NetworkService.ethernetAvailable) {
                      panelViewMode = "ethernet";
                    } else {
                      TooltipService.show(parent, I18n.tr("wifi.panel.no-ethernet-devices"));
                    }
                  } else if (panelViewMode === "ethernet") {
                    panelViewMode = "wifi";
                  } else {
                    panelViewMode = "wifi";
                  }
                }
                onEntered: TooltipService.show(parent, panelViewMode === "wifi" ? I18n.tr("common.wifi") : panelViewMode === "ethernet" ? I18n.tr("common.ethernet") : "VPN")
                onExited: TooltipService.hide()
              }
            }

            NLabel {
              label: panelViewMode === "wifi" ? I18n.tr("common.wifi") : panelViewMode === "ethernet" ? I18n.tr("common.ethernet") : "VPN"
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
              icon: "refresh"
              visible: panelViewMode === "vpn"
              tooltipText: I18n.tr("common.refresh")
              baseSize: Style.baseWidgetSize * 0.8
              enabled: !VPNService.refreshing
              onClicked: VPNService.refresh()
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

          // Mode switch (Wi‑Fi / Ethernet / VPN)
          NTabBar {
            id: modeTabBar
            visible: {
              let count = 0;
              if (NetworkService.wifiAvailable) count++;
              if (NetworkService.ethernetAvailable) count++;
              if (root.vpnAvailable) count++;
              return count > 1;
            }
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
              visible: NetworkService.wifiAvailable
            }

            NTabButton {
              text: I18n.tr("common.ethernet")
              tabIndex: 1
              checked: modeTabBar.currentIndex === 1
              visible: NetworkService.ethernetAvailable
            }

            NTabButton {
              text: "VPN"
              tabIndex: 2
              checked: modeTabBar.currentIndex === 2
              visible: root.vpnAvailable
            }
          }
        }
      }

      // Unified scrollable content (Wi‑Fi or Ethernet view)
      ColumnLayout {
        id: wifiSectionContainer
        visible: true
        Layout.fillWidth: true
        spacing: Style.marginM

        // Error message
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

        // Unified scrollable content
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

            // Wi‑Fi disabled state
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
            }

            // Scanning state (show when no networks and we haven't had any yet)
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

                Item {
                  Layout.fillHeight: true
                }

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

                Item {
                  Layout.fillHeight: true
                }
              }
            }

            // Empty state when no networks (only show after we've had networks before, meaning a real empty result)
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

                Item {
                  Layout.fillHeight: true
                }

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

                Item {
                  Layout.fillHeight: true
                }
              }
            }

            // Networks list container (Wi‑Fi)
            ColumnLayout {
              id: networksList
              visible: panelViewMode === "wifi" && NetworkService.wifiEnabled && Object.keys(NetworkService.networks).length > 0
              width: parent.width
              spacing: Style.marginM

              WifiPrefs.WifiSubTab {
                showOnlyLists: true
              }
            }

            // Ethernet view
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

                // Section label
                NLabel {
                  label: I18n.tr("wifi.panel.available-interfaces")
                  visible: (NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0)
                }

                // Empty state when no Ethernet devices
                ColumnLayout {
                  id: emptyEthColumn

                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
                  Layout.preferredHeight: emptyEthColumn.implicitHeight + Style.margin2M
                  visible: !(NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0)
                  spacing: Style.marginL

                  Item {
                    Layout.fillHeight: true
                  }

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

                  Item {
                    Layout.fillHeight: true
                  }
                }

                // Interfaces list
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

                        // Main row matching Wi‑Fi card style
                        // Click handling for the whole header row is provided by a sibling MouseArea
                        // anchored to this row (defined right after this RowLayout).
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

                              // Network speed indicators (visible when connected and speed > 0)
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

                          // Info button on the right
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

                        // Click handling without anchors in a Layout-managed item
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

                        // Inline Ethernet details
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

                          // Grid/List toggle
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

                            // --- Item 1: Interface ---
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

                                // Click-to-copy Ethernet interface name
                                MouseArea {
                                  anchors.fill: parent
                                  // Guard against undefined by normalizing to empty strings
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

                            // --- Item 2: Hardware Address ---
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

                            // --- Item 3: Link speed ---
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

                            // --- Item 4: IPv4 || IPv6 ---
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

                                // Click-to-copy Ethernet IP address
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

                            // --- Item 5: DNS ---
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

                                // Click-to-copy Ethernet DNS
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

                            // --- Item 6: Gateway ---
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

                                // Click-to-copy Ethernet Gateway
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

            // VPN error message
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

            // VPN Connected section
            NBox {
              visible: panelViewMode === "vpn" && VPNService.activeConnections.length > 0
              Layout.fillWidth: true
              Layout.preferredHeight: vpnConnectedColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: vpnConnectedColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                NLabel {
                  label: I18n.tr("common.connected")
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginXS

                  Repeater {
                    model: VPNService.activeConnections

                    delegate: NBox {
                      Layout.fillWidth: true
                      Layout.leftMargin: Style.marginXS
                      Layout.rightMargin: Style.marginXS
                      implicitHeight: vpnActiveRow.implicitHeight + Style.marginXL
                      color: Qt.alpha(Color.mPrimary, 0.15)

                      RowLayout {
                        id: vpnActiveRow
                        width: parent.width - Style.marginXL
                        x: Style.marginM
                        y: Style.marginM
                        spacing: Style.marginS

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
                            pointSize: Style.fontSizeM
                            font.weight: Style.fontWeightMedium
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                          }

                          RowLayout {
                            spacing: Style.marginXS

                            NText {
                              text: modelData.type || "vpn"
                              pointSize: Style.fontSizeXXS
                              color: Color.mOnSurfaceVariant
                            }

                            Rectangle {
                              color: Color.mPrimary
                              radius: height * 0.5
                              width: Math.round(connectedBadgeText.implicitWidth + Style.marginS * 2)
                              height: Math.round(connectedBadgeText.implicitHeight + Style.marginXS)

                              NText {
                                id: connectedBadgeText
                                anchors.centerIn: parent
                                text: (VPNService.disconnecting && VPNService.disconnectingUuid === modelData.uuid) ? I18n.tr("common.disconnecting") : I18n.tr("common.connected")
                                pointSize: Style.fontSizeXXS
                                color: Color.mOnPrimary
                              }
                            }
                          }
                        }

                        NBusyIndicator {
                          visible: VPNService.disconnecting && VPNService.disconnectingUuid === modelData.uuid
                          running: visible && root.effectivelyVisible
                          color: Color.mPrimary
                          size: Style.baseWidgetSize * 0.5
                        }

                        NButton {
                          text: I18n.tr("common.disconnect")
                          outlined: !hovered
                          fontSize: Style.fontSizeS
                          backgroundColor: Color.mError
                          enabled: !VPNService.disconnecting
                          onClicked: VPNService.disconnect(modelData.uuid)
                        }
                      }
                    }
                  }
                }
              }
            }

            // VPN Available (inactive) section
            NBox {
              visible: panelViewMode === "vpn" && VPNService.inactiveConnections.length > 0
              Layout.fillWidth: true
              Layout.preferredHeight: vpnAvailableColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: vpnAvailableColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginM

                NLabel {
                  label: I18n.tr("common.disconnected")
                }

                Repeater {
                  model: VPNService.inactiveConnections

                  delegate: NBox {
                    Layout.fillWidth: true
                    Layout.leftMargin: Style.marginXS
                    Layout.rightMargin: Style.marginXS
                    implicitHeight: vpnInactiveRow.implicitHeight + Style.marginXL
                    color: Color.mSurface

                    RowLayout {
                      id: vpnInactiveRow
                      width: parent.width - Style.marginXL
                      x: Style.marginM
                      y: Style.marginM
                      spacing: Style.marginS

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
                          pointSize: Style.fontSizeM
                          font.weight: Style.fontWeightMedium
                          color: Color.mOnSurface
                          elide: Text.ElideRight
                          Layout.fillWidth: true
                        }

                        NText {
                          text: modelData.type || "vpn"
                          pointSize: Style.fontSizeXXS
                          color: Color.mOnSurfaceVariant
                        }
                      }

                      NBusyIndicator {
                        visible: VPNService.connecting && VPNService.connectingUuid === modelData.uuid
                        running: visible && root.effectivelyVisible
                        color: Color.mPrimary
                        size: Style.baseWidgetSize * 0.5
                      }

                      NButton {
                        text: (VPNService.connecting && VPNService.connectingUuid === modelData.uuid) ? I18n.tr("common.connecting") : I18n.tr("common.connect")
                        outlined: !hovered
                        fontSize: Style.fontSizeS
                        enabled: !VPNService.connecting
                        onClicked: VPNService.connect(modelData.uuid)
                      }
                    }
                  }
                }
              }
            }

            // VPN empty state
            NBox {
              visible: panelViewMode === "vpn" && Object.keys(VPNService.connections).length === 0
              Layout.fillWidth: true
              Layout.preferredHeight: emptyVpnColumn.implicitHeight + Style.margin2M

              ColumnLayout {
                id: emptyVpnColumn
                anchors.fill: parent
                anchors.margins: Style.marginM
                spacing: Style.marginL

                Item {
                  Layout.fillHeight: true
                }

                NIcon {
                  icon: "shield-off"
                  pointSize: 48
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: I18n.tr("tooltips.manage-vpn")
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                Item {
                  Layout.fillHeight: true
                }
              }
            }
          }
        }
      }
    }
  }
}

