import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Modules.Panels.Settings
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(500 * Style.uiScaleRatio)

  property string passwordSsid: ""
  property string expandedSsid: ""

  // Info panel collapsed by default, view mode persisted under Settings.data.ui.wifiDetailsViewMode
  // Ethernet details UI state (mirrors Wi‑Fi info behavior)
  property bool ethernetInfoExpanded: false
  property bool ethernetDetailsGrid: (Settings.data && Settings.data.ui && Settings.data.network.wifiDetailsViewMode !== undefined) ? (Settings.data.network.wifiDetailsViewMode === "grid") : true

  // Unified panel view mode: "wifi" | "ethernet" (persisted)
  property string panelViewMode: "wifi"
  property bool panelViewPersistEnabled: false

  onPanelViewModeChanged: {
    // Persist last view (only after restored the initial value)
    if (panelViewPersistEnabled && Settings.data && Settings.data.ui && Settings.data.ui.networkPanelView !== undefined)
      Settings.data.ui.networkPanelView = panelViewMode;
    // Reset transient states to avoid layout artifacts
    passwordSsid = "";
    expandedSsid = "";
    if (panelViewMode === "wifi") {
      ethernetInfoExpanded = false;
      if (Settings.data.network.wifiEnabled && !NetworkService.scanning && Object.keys(NetworkService.networks).length === 0)
        NetworkService.scan();
    } else {
      if (NetworkService.ethernetConnected) {
        NetworkService.refreshActiveEthernetDetails();
      } else {
        NetworkService.refreshEthernet();
      }
    }
  }

  // Computed network lists
  readonly property var knownNetworks: {
    if (!Settings.data.network.wifiEnabled)
      return [];

    var nets = Object.values(NetworkService.networks);
    var known = nets.filter(n => n.connected || n.existing || n.cached);

    // Sort: connected first, then by signal strength
    known.sort((a, b) => {
                 if (a.connected !== b.connected)
                 return b.connected - a.connected;
                 return b.signal - a.signal;
               });

    return known;
  }
  onOpened: {
    NetworkService.scan();
    // Preload active Wi‑Fi details so Info shows instantly
    NetworkService.refreshActiveWifiDetails();
    // Also fetch Ethernet details if connected
    NetworkService.refreshActiveEthernetDetails();
    // Restore last view if valid, otherwise choose what's available (prefer Wi‑Fi when both exist)
    if (Settings.data && Settings.data.ui && Settings.data.ui.networkPanelView) {
      const last = Settings.data.ui.networkPanelView;
      if (last === "ethernet" && NetworkService.hasEthernet()) {
        panelViewMode = "ethernet";
      } else {
        panelViewMode = "wifi";
      }
    } else {
      if (!Settings.data.network.wifiEnabled && NetworkService.hasEthernet())
        panelViewMode = "ethernet";
      else
        panelViewMode = "wifi";
    }
    panelViewPersistEnabled = true;
  }

  readonly property var availableNetworks: {
    if (!Settings.data.network.wifiEnabled)
      return [];

    var nets = Object.values(NetworkService.networks);
    var available = nets.filter(n => !n.connected && !n.existing && !n.cached);

    // Sort by signal strength
    available.sort((a, b) => b.signal - a.signal);

    return available;
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
              icon: panelViewMode === "wifi" ? (Settings.data.network.wifiEnabled ? "wifi" : "wifi-off") : (NetworkService.hasEthernet() ? (NetworkService.ethernetConnected ? "ethernet" : "ethernet") : "ethernet-off")
              pointSize: Style.fontSizeXXL
              color: panelViewMode === "wifi" ? (Settings.data.network.wifiEnabled ? Color.mPrimary : Color.mOnSurfaceVariant) : (NetworkService.ethernetConnected ? Color.mPrimary : Color.mOnSurfaceVariant)
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                  if (panelViewMode === "wifi") {
                    if (NetworkService.hasEthernet()) {
                      panelViewMode = "ethernet";
                    } else {
                      TooltipService.show(parent, I18n.tr("wifi.panel.no-ethernet-devices"));
                    }
                  } else {
                    panelViewMode = "wifi";
                  }
                }
                onEntered: TooltipService.show(parent, panelViewMode === "wifi" ? I18n.tr("common.ethernet") : I18n.tr("common.wifi"))
                onExited: TooltipService.hide()
              }
            }

            NLabel {
              label: panelViewMode === "wifi" ? I18n.tr("common.wifi") : I18n.tr("common.ethernet")
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "refresh"
              tooltipText: I18n.tr("common.refresh")
              baseSize: Style.baseWidgetSize * 0.8
              enabled: panelViewMode === "wifi" ? (Settings.data.network.wifiEnabled && !NetworkService.scanning) : true
              onClicked: {
                if (panelViewMode === "wifi")
                  NetworkService.scan();
                else
                  NetworkService.refreshEthernet();
              }
            }

            NToggle {
              id: wifiSwitch
              visible: panelViewMode === "wifi"
              checked: Settings.data.network.wifiEnabled
              enabled: !Settings.data.network.airplaneModeEnabled && NetworkService.wifiAvailable
              onToggled: checked => NetworkService.setWifiEnabled(checked)
              baseSize: Style.baseWidgetSize * 0.7 // Slightly smaller
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

          // Mode switch (Wi‑Fi / Ethernet)
          NTabBar {
            id: modeTabBar
            visible: NetworkService.hasEthernet()
            margins: Style.marginS
            Layout.fillWidth: true
            spacing: Style.marginM
            distributeEvenly: true
            currentIndex: root.panelViewMode === "wifi" ? 0 : 1
            onCurrentIndexChanged: {
              root.panelViewMode = (currentIndex === 0) ? "wifi" : "ethernet";
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
              visible: panelViewMode === "wifi" && !Settings.data.network.wifiEnabled
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
              visible: panelViewMode === "wifi" && Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length === 0 && NetworkService.scanning
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
            }

            // Empty state when no networks (only show after we've had networks before, meaning a real empty result)
            NBox {
              id: emptyBox
              visible: panelViewMode === "wifi" && Settings.data.network.wifiEnabled && !NetworkService.scanning && Object.keys(NetworkService.networks).length === 0 && !NetworkService.scanning
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
                  icon: "search"
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

            // Networks list container (Wi‑Fi)
            ColumnLayout {
              id: networksList
              visible: panelViewMode === "wifi" && Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length > 0
              width: parent.width
              spacing: Style.marginM

              WiFiNetworksList {
                label: I18n.tr("wifi.panel.known-networks")
                model: root.knownNetworks
                passwordSsid: root.passwordSsid
                expandedSsid: root.expandedSsid
                onPasswordRequested: ssid => {
                                       root.passwordSsid = ssid;
                                       root.expandedSsid = "";
                                     }
                onPasswordSubmitted: (ssid, password) => {
                                       NetworkService.connect(ssid, password);
                                       root.passwordSsid = "";
                                     }
                onPasswordCancelled: root.passwordSsid = ""
                onForgetRequested: ssid => root.expandedSsid = root.expandedSsid === ssid ? "" : ssid
                onForgetConfirmed: ssid => {
                                     NetworkService.forget(ssid);
                                     root.expandedSsid = "";
                                   }
                onForgetCancelled: root.expandedSsid = ""
              }

              WiFiNetworksList {
                label: I18n.tr("wifi.panel.available-networks")
                model: root.availableNetworks
                passwordSsid: root.passwordSsid
                expandedSsid: root.expandedSsid
                onPasswordRequested: ssid => {
                                       root.passwordSsid = ssid;
                                       root.expandedSsid = "";
                                     }
                onPasswordSubmitted: (ssid, password) => {
                                       NetworkService.connect(ssid, password);
                                       root.passwordSsid = "";
                                     }
                onPasswordCancelled: root.passwordSsid = ""
                onForgetRequested: ssid => root.expandedSsid = root.expandedSsid === ssid ? "" : ssid
                onForgetConfirmed: ssid => {
                                     NetworkService.forget(ssid);
                                     root.expandedSsid = "";
                                   }
                onForgetCancelled: root.expandedSsid = ""
              }
            }

            // Ethernet view
            ColumnLayout {
              id: ethernetSection
              visible: panelViewMode === "ethernet"
              width: parent.width
              spacing: Style.marginM

              // Section label
              NText {
                text: I18n.tr("wifi.panel.available-interfaces")
                pointSize: Style.fontSizeM
                color: Color.mOnSurface
              }

              // Empty state when no Ethernet devices
              NBox {
                visible: !(NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0)
                Layout.fillWidth: true
                Layout.preferredHeight: emptyEthColumn.implicitHeight + Style.margin2M

                ColumnLayout {
                  id: emptyEthColumn
                  anchors.fill: parent
                  anchors.margins: Style.marginM
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

                    Layout.fillWidth: true
                    Layout.leftMargin: Style.marginXS
                    Layout.rightMargin: Style.marginXS
                    implicitHeight: ethItemColumn.implicitHeight + Style.margin2M
                    radius: Style.radiusM
                    border.width: Style.borderS
                    border.color: modelData.connected ? Color.mPrimary : Color.mOutline
                    color: modelData.connected ? Qt.rgba(Color.mPrimary.r, Color.mPrimary.g, Color.mPrimary.b, 0.05) : Color.mSurface

                    ColumnLayout {
                      id: ethItemColumn
                      width: parent.width - Style.margin2M
                      x: Style.marginM
                      y: Style.marginM
                      spacing: Style.marginS

                      // Main row matching Wi‑Fi card style
                      RowLayout {
                        id: ethHeaderRow
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        // Click handling for the whole header row is provided by a sibling MouseArea
                        // anchored to this row (defined right after this RowLayout).

                        NIcon {
                          icon: "ethernet"
                          pointSize: Style.fontSizeXXL
                          color: modelData.connected ? Color.mPrimary : Color.mOnSurface
                        }

                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 2

                          NText {
                            text: modelData.ifname
                            pointSize: Style.fontSizeM
                            font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
                            color: Color.mOnSurface
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                          }

                          RowLayout {
                            spacing: Style.marginXS

                            // Connected badge (mirrors Wi‑Fi chip)
                            Rectangle {
                              visible: modelData.connected
                              color: Color.mPrimary
                              radius: height * 0.5
                              width: ethConnectedText.implicitWidth + Style.margin2S
                              height: ethConnectedText.implicitHeight + (Style.margin2XXS)

                              NText {
                                id: ethConnectedText
                                anchors.centerIn: parent
                                text: I18n.tr("common.connected")
                                pointSize: Style.fontSizeXXS
                                color: Color.mOnPrimary
                              }
                            }
                          }
                        }

                        // Info button on the right
                        NIconButton {
                          icon: "info"
                          tooltipText: I18n.tr("common.info")
                          baseSize: Style.baseWidgetSize * 0.8
                          enabled: true
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
                        radius: Style.radiusS
                        border.width: Style.borderS
                        border.color: Color.mOutline
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
                          baseSize: Style.baseWidgetSize * 0.8
                          onClicked: {
                            ethernetDetailsGrid = !ethernetDetailsGrid;
                            if (Settings.data && Settings.data.ui) {
                              Settings.data.ui.wifiDetailsViewMode = ethernetDetailsGrid ? "grid" : "list";
                            }
                          }
                          z: 1
                        }

                        GridLayout {
                          id: ethInfoGrid
                          anchors.fill: parent
                          anchors.margins: Style.marginS
                          anchors.rightMargin: Style.baseWidgetSize
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
                          // Grid: Row 0, Col 0 | List: Row 0
                          RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            spacing: Style.marginXS
                            Layout.row: 0
                            Layout.column: 0
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
                                    ToastService.showNotice(I18n.tr("common.ethernet"), I18n.tr("toast.bluetooth.address-copied"), "ethernet");
                                  }
                                }
                              }
                            }
                          }

                          // --- Item 2: Internet connectivity --
                          // Grid: Row 1, Col 0 | List: Row 1
                          RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.row: 1
                            Layout.column: 0
                            spacing: Style.marginXS
                            NIcon {
                              // If the selected Ethernet interface is disconnected, show an explicit disconnected state
                              icon: modelData.connected ? (NetworkService.internetConnectivity ? "world" : "world-off") : "world-off"
                              pointSize: Style.fontSizeXS
                              color: modelData.connected ? (NetworkService.internetConnectivity ? Color.mOnSurface : Color.mError) : Color.mError
                              Layout.alignment: Qt.AlignVCenter
                              MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.internet-status"))
                                onExited: TooltipService.hide()
                              }
                            }
                            NText {
                              // Show "Disconnected" when the interface itself is down
                              text: modelData.connected ? (NetworkService.internetConnectivity ? I18n.tr("wifi.panel.internet-connected") : I18n.tr("wifi.panel.internet-limited")) : I18n.tr("common.disconnected")
                              pointSize: Style.fontSizeXS
                              color: modelData.connected ? (NetworkService.internetConnectivity ? Color.mOnSurface : Color.mError) : Color.mError
                              Layout.fillWidth: true
                              Layout.alignment: Qt.AlignVCenter
                              wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                              elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                              maximumLineCount: ethernetDetailsGrid ? 1 : 6
                              clip: true
                            }
                          }

                          // --- Iterm 3: Link speed ---
                          // Grid: Row 2, Col 0 | List: Row 2
                          RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.row: 2
                            Layout.column: 0
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

                          // --- Item 4: Gateway ---
                          // Grid: Row 2, Col 1 | List: Row 5 (Last)
                          RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.row: ethernetDetailsGrid ? 2 : 5
                            Layout.column: ethernetDetailsGrid ? 1 : 0
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
                              text: NetworkService.activeEthernetDetails.gateway4 || "-"
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

                          // --- Item 5: IPv4 ---
                          // Grid: Row 0, Col 1 | List: Row 3
                          RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.row: ethernetDetailsGrid ? 0 : 3
                            Layout.column: ethernetDetailsGrid ? 1 : 0
                            spacing: Style.marginXS
                            NIcon {
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
                              text: NetworkService.activeEthernetDetails.ipv4 || "-"
                              pointSize: Style.fontSizeXS
                              color: Color.mOnSurface
                              Layout.fillWidth: true
                              Layout.alignment: Qt.AlignVCenter
                              wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                              elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                              maximumLineCount: ethernetDetailsGrid ? 1 : 6
                              clip: true

                              // Click-to-copy Ethernet IPv4 address
                              MouseArea {
                                anchors.fill: parent
                                // Normalize to string to avoid undefined -> bool assignment warnings
                                enabled: (NetworkService.activeEthernetDetails.ipv4 || "").length > 0
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                                onExited: TooltipService.hide()
                                onClicked: {
                                  const value = NetworkService.activeEthernetDetails.ipv4 || "";
                                  if (value.length > 0) {
                                    Quickshell.execDetached(["wl-copy", value]);
                                    ToastService.showNotice(I18n.tr("common.ethernet"), I18n.tr("toast.bluetooth.address-copied"), "ethernet");
                                  }
                                }
                              }
                            }
                          }

                          // --- Item 6: DNS ---
                          // Grid: Row 1, Col 1 | List: Row 4
                          RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.row: ethernetDetailsGrid ? 1 : 4
                            Layout.column: ethernetDetailsGrid ? 1 : 0
                            spacing: Style.marginXS
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
                              text: NetworkService.activeEthernetDetails.dns || "-"
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
