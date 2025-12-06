import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Networking
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(420 * Style.uiScaleRatio)
  preferredHeight: Math.round(500 * Style.uiScaleRatio)

  property string passwordSsid: ""
  property string expandedSsid: ""
  property bool hasHadNetworks: false

  // Computed network lists
  readonly property var knownNetworks: {
    if (!Settings.data.network.wifiEnabled)
      return [];

    const nets = Object.values(NetworkService.networks);
    const known = nets.filter(n => n.connected || n.existing || n.cached);

    // Sort: connected first, then by signal strength
    known.sort((a, b) => {
                 if (a.connected !== b.connected)
                 return b.connected - a.connected;
                 return b.signal - a.signal;
               });

    return known;
  }

  readonly property var availableNetworks: {
    if (!Settings.data.network.wifiEnabled)
      return [];

    const nets = Object.values(NetworkService.networks);
    const available = nets.filter(n => !n.connected && !n.existing && !n.cached);

    // Sort by signal strength
    available.sort((a, b) => b.signal - a.signal);

    return available;
  }

  onOpened: {
    hasHadNetworks = false;
    NetworkService.scan();
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
    property real networksHeight: networksList.implicitHeight
    property real calculatedHeight: (networksHeight !== 0) ? (headerHeight + networksHeight + Style.marginL * 2 + Style.marginM) : (280 * Style.uiScaleRatio)
    property real contentPreferredHeight: Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length > 0 ? Math.min(root.preferredHeight, calculatedHeight) : Math.min(root.preferredHeight, 280 * Style.uiScaleRatio)

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

      // WiFi disabled state
      NBox {
        visible: !Settings.data.network.wifiEnabled
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
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
        visible: Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length === 0 && !root.hasHadNetworks
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
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
        visible: Settings.data.network.wifiEnabled && !NetworkService.scanning && Object.keys(NetworkService.networks).length === 0 && root.hasHadNetworks
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
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

      // Networks list container (no NBox wrapper)
      NScrollView {
        visible: Settings.data.network.wifiEnabled && Object.keys(NetworkService.networks).length > 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        clip: true

        ColumnLayout {
          id: networksList
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
