import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(500 * Style.uiScaleRatio)

  property string passwordSsid: ""
  property string expandedSsid: ""
  property bool hasHadNetworks: false

  // Ethernet details UI state (mirrors Wi‑Fi info behavior)
  // Info panel collapsed by default, view mode persisted under Settings.data.ui.wifiDetailsViewMode
  property bool ethernetInfoExpanded: false
  property bool ethernetDetailsGrid: (Settings.data && Settings.data.ui && Settings.data.ui.wifiDetailsViewMode !== undefined) ? (Settings.data.ui.wifiDetailsViewMode === "grid") : true

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
    hasHadNetworks = false;
    NetworkService.scan();
    // Preload active Wi‑Fi details so Info shows instantly
    NetworkService.refreshActiveWifiDetails();
    // Also fetch Ethernet details if connected
    NetworkService.refreshActiveEthernetDetails();
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

  onKnownNetworksChanged: {
    if (knownNetworks.length > 0)
      hasHadNetworks = true;
  }

  onAvailableNetworksChanged: {
    if (availableNetworks.length > 0)
      hasHadNetworks = true;
  }

  Connections {
    target: Settings.data.network
    function onWifiEnabledChanged() {
      if (!Settings.data.network.wifiEnabled)
        root.hasHadNetworks = false;
    }
  }

  panelContent: Rectangle {
    color: Color.transparent

    // Calculate content height based on header + networks list (or minimum for empty states)
    property real headerHeight: headerRow.implicitHeight + Style.marginM * 2
    // Height of the Ethernet card when visible (placed above header)
    property real ethernetHeight: NetworkService.ethernetConnected ? (ethColumn.implicitHeight + Style.marginM * 2 + Style.marginM) : 0
    property real networksHeight: networksList.implicitHeight
    // When there are networks, include their height; otherwise reserve a baseline block height.
    property real stateBlockBaseline: 280 * Style.uiScaleRatio
    property real calculatedHeight: {
      const base = headerHeight + ethernetHeight + Style.marginL * 2 + Style.marginM;
      if (Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length > 0)
        return base + networksHeight;
      // Wi‑Fi disabled / scanning / empty states (non-scroll blocks). Use baseline but include Ethernet card height.
      return base + stateBlockBaseline;
    }
    property real contentPreferredHeight: Math.min(root.preferredHeight, calculatedHeight)

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // Ethernet info (shown when Ethernet is connected)
      NBox {
        visible: NetworkService.ethernetConnected
        Layout.fillWidth: true
        Layout.preferredHeight: ethColumn.implicitHeight + Style.marginM * 2

        ColumnLayout {
          id: ethColumn
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          // Title row
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NIcon {
              icon: NetworkService.internetConnectivity ? "ethernet" : "ethernet-off"
              pointSize: Style.fontSizeXXL
              color: NetworkService.internetConnectivity ? Color.mPrimary : Color.mError
            }

            // Fixed header label (match design with Wi‑Fi/Bluetooth)
            NText {
              text: I18n.tr("quickSettings.wifi.label.ethernet")
              pointSize: Style.fontSizeL
              font.weight: Style.fontWeightBold
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            // Info toggle (behaves like Wi‑Fi info button)
            NIconButton {
              icon: "info-circle"
              tooltipText: I18n.tr("wifi.panel.info")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                ethernetInfoExpanded = !ethernetInfoExpanded;
                if (ethernetInfoExpanded)
                  NetworkService.refreshActiveEthernetDetails();
              }
            }

            // Close button (shown on Ethernet bar when Ethernet is available)
            NIconButton {
              visible: NetworkService.ethernetConnected
              icon: "close"
              tooltipText: I18n.tr("tooltips.close")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.close()
            }
          }

          // Details container with grid/list view toggle
          Rectangle {
            id: ethInfoContainer
            visible: ethernetInfoExpanded
            Layout.fillWidth: true
            color: Color.mSurfaceVariant
            radius: Style.radiusS
            border.width: Style.borderS
            border.color: Color.mOutline
            implicitHeight: ethInfoGrid.implicitHeight + Style.marginS * 2
            clip: true
            onVisibleChanged: {
              if (visible && ethInfoGrid && ethInfoGrid.forceLayout) {
                Qt.callLater(function () {
                  ethInfoGrid.forceLayout();
                });
              }
            }

            // Grid/List toggle at top-right
            NIconButton {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.marginS
              icon: ethernetDetailsGrid ? "layout-list" : "layout-grid"
              tooltipText: ethernetDetailsGrid ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
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

              // Interface name (first)
              RowLayout {
                Layout.fillWidth: true
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
                }
              }

              // Internet connectivity (moved up to match Wi‑Fi layout)
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: NetworkService.internetConnectivity ? "world" : "world-off"
                  pointSize: Style.fontSizeXS
                  color: NetworkService.internetConnectivity ? Color.mOnSurface : Color.mError
                  Layout.alignment: Qt.AlignVCenter
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
                  Layout.alignment: Qt.AlignVCenter
                  wrapMode: ethernetDetailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: ethernetDetailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: ethernetDetailsGrid ? 1 : 6
                  clip: true
                }
              }

              // Link speed (placed after Internet to match Wi‑Fi grid ordering)
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

              // IPv4 address
              RowLayout {
                Layout.fillWidth: true
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
                }
              }

              // Gateway
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
                    onEntered: TooltipService.show(parent, I18n.tr("wifi.panel.gateway"))
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

              // DNS
              RowLayout {
                Layout.fillWidth: true
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
            // Hide this header close button when Ethernet is available; the close button moves to the Ethernet bar
            visible: !NetworkService.ethernetConnected
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

      // Unified scrollable content so elements scale and never spill out
      NScrollView {
        id: contentScroll
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        clip: true

        ColumnLayout {
          id: contentColumn
          width: parent.width
          spacing: Style.marginM

          // Wi‑Fi disabled state (moved inside the scroll)
          NBox {
            id: disabledBox
            visible: !Settings.data.network.wifiEnabled
            Layout.fillWidth: true
            Layout.preferredHeight: disabledColumn.implicitHeight + Style.marginM * 2

            ColumnLayout {
              id: disabledColumn
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
          }

          // Scanning state (show when no networks and we haven't had any yet)
          NBox {
            id: scanningBox
            visible: Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length === 0 && !root.hasHadNetworks
            Layout.fillWidth: true
            Layout.preferredHeight: scanningColumn.implicitHeight + Style.marginM * 2

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
            visible: Settings.data.network.wifiEnabled && !NetworkService.scanning && Object.keys(NetworkService.networks).length === 0 && root.hasHadNetworks
            Layout.fillWidth: true
            Layout.preferredHeight: emptyColumn.implicitHeight + Style.marginM * 2

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

          // Networks list container (moved into the scroll, keep id for height calc)
          ColumnLayout {
            id: networksList
            visible: Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length > 0
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
        }
      }
    }
  }
}
