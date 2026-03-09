import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Bluetooth

import qs.Commons
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: root
  Layout.fillWidth: true
  implicitHeight: mainLayout.implicitHeight

  // Configuration for shared use (e.g. by NetworkPanel)
  property bool showOnlyLists: false

  // State properties
  property string passwordSsid: ""
  property string identity: ""
  property string expandedSsid: ""
  property string infoSsid: ""
  property int ipVersion: 4
  property bool detailsGrid: (Settings.data && Settings.data.network && Settings.data.network.wifiDetailsViewMode === "grid")

  // Freezing models for password entry
  property var cachedNetworks: ({})

  onPasswordSsidChanged: {
    if (passwordSsid && passwordSsid.length > 0) {
      try {
        cachedNetworks = JSON.parse(JSON.stringify(NetworkService.networks));
      } catch (e) {
        cachedNetworks = Object.assign({}, NetworkService.networks);
      }
    } else {
      cachedNetworks = ({});
    }
  }

  readonly property var activeNetworks: (passwordSsid && passwordSsid.length > 0) ? Object.values(cachedNetworks) : Object.values(NetworkService.networks)

  readonly property var connectedNetworks: {
    if (!Settings.data.network.wifiEnabled) {
      return [];
    }
    return activeNetworks.filter(n => n.connected).sort((a, b) => b.signal - a.signal);
  }

  readonly property var savedNetworks: {
    if (!Settings.data.network.wifiEnabled) {
      return [];
    }
    return activeNetworks.filter(n => !n.connected && (n.existing || n.cached)).sort((a, b) => b.signal - a.signal);
  }

  readonly property var availableNetworks: {
    if (!Settings.data.network.wifiEnabled) {
      return [];
    }
    return activeNetworks.filter(n => !n.connected && !n.existing && !n.cached).sort((a, b) => b.signal - a.signal);
  }

  // Combined visibility check: tab must be visible AND the window must be visible
  readonly property bool effectivelyVisible: root.visible && Window.window && Window.window.visible

  onEffectivelyVisibleChanged: {
    if (effectivelyVisible && Settings.data.network.wifiEnabled && !showOnlyLists) {
      NetworkService.scan();
    }
    if (effectivelyVisible) {
      SystemStatService.registerComponent("wifi-subtab");
    } else {
      SystemStatService.unregisterComponent("wifi-subtab");
    }
  }

  Component.onCompleted: {
    if (effectivelyVisible) {
      SystemStatService.registerComponent("wifi-subtab");
    }
  }

  Component.onDestruction: {
    SystemStatService.unregisterComponent("wifi-subtab");
  }

  // Actions
  function requestPassword(ssid) {
    passwordSsid = ssid;
    identity = "";
    expandedSsid = "";
  }
  function submitPassword(ssid, password, identity = "") {
    NetworkService.connect(ssid, password, false, identity);
    passwordSsid = "";
  }
  function cancelPassword() {
    passwordSsid = "";
  }
  function requestForget(ssid) {
    expandedSsid = (expandedSsid === ssid) ? "" : ssid;
  }
  function confirmForget(ssid) {
    NetworkService.forget(ssid);
    expandedSsid = "";
  }
  function cancelForget() {
    expandedSsid = "";
  }

  ColumnLayout {
    id: mainLayout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.marginL

    // Master Control Section
    NBox {
      visible: !root.showOnlyLists
      Layout.fillWidth: true
      Layout.preferredHeight: masterControlCol.implicitHeight + Style.margin2L
      color: Color.mSurface

      ColumnLayout {
        id: masterControlCol
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          NToggle {
            label: I18n.tr("common.wifi")
            icon: {
              if (!Settings.data.network.wifiEnabled) {
                return "wifi-off";
              }
              if (root.connectedNetworks.length > 0) {
                const net = root.connectedNetworks[0];
                return NetworkService.signalIcon(net.signal, true);
              }
              return "wifi";
            }
            checked: Settings.data.network.wifiEnabled
            onToggled: checked => NetworkService.setWifiEnabled(checked)
            enabled: ProgramCheckerService.nmcliAvailable && !Settings.data.network.airplaneModeEnabled && NetworkService.wifiAvailable
            Layout.alignment: Qt.AlignVCenter
          }
        }

        NDivider {
          Layout.fillWidth: true
          visible: Settings.data.network.wifiEnabled && root.connectedNetworks.length > 0
        }

        NText {
          visible: !root.showOnlyLists && Settings.data.network.wifiEnabled
          Layout.fillWidth: true
          text: I18n.tr("panels.connections.wifi-header-text")
          color: Color.mOnSurfaceVariant
          richTextEnabled: true
          wrapMode: Text.WordWrap
          horizontalAlignment: Text.AlignHCenter
        }
      }
    }

    Item {
      visible: !showOnlyLists
      Layout.fillWidth: true
    }

    // Network List [1] (Connected)
    NBox {
      id: connectedBox
      visible: root.connectedNetworks.length > 0 && Settings.data.network.wifiEnabled
      Layout.fillWidth: true
      Layout.preferredHeight: connectedCol.implicitHeight + Style.margin2M
      border.color: showOnlyLists ? Style.boxBorderColor : "transparent"

      ColumnLayout {
        id: connectedCol
        anchors.fill: parent
        anchors.topMargin: Style.marginM
        anchors.bottomMargin: Style.marginM
        anchors.leftMargin: showOnlyLists ? Style.marginL : 0
        anchors.rightMargin: showOnlyLists ? Style.marginL : 0
        spacing: Style.marginM

        NLabel {
          label: I18n.tr("common.connected")
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
        }

        Repeater {
          model: root.connectedNetworks
          delegate: nboxDelegate
        }
      }
    }

    // Network List [2] (Saved)
    NBox {
      id: savedBox
      visible: root.savedNetworks.length > 0 && Settings.data.network.wifiEnabled
      Layout.fillWidth: true
      Layout.preferredHeight: savedCol.implicitHeight + Style.margin2M
      border.color: showOnlyLists ? Style.boxBorderColor : "transparent"

      ColumnLayout {
        id: savedCol
        anchors.fill: parent
        anchors.topMargin: Style.marginM
        anchors.bottomMargin: Style.marginM
        anchors.leftMargin: showOnlyLists ? Style.marginL : 0
        anchors.rightMargin: showOnlyLists ? Style.marginL : 0
        spacing: Style.marginM

        NLabel {
          label: I18n.tr("wifi.panel.known-networks")
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
        }

        Repeater {
          model: root.savedNetworks
          delegate: nboxDelegate
        }
      }
    }

    // Network List [3] (Available)
    NBox {
      id: availableBox
      visible: root.availableNetworks.length > 0 && Settings.data.network.wifiEnabled
      Layout.fillWidth: true
      Layout.preferredHeight: availableCol.implicitHeight + Style.margin2M
      border.color: showOnlyLists ? Style.boxBorderColor : "transparent"

      ColumnLayout {
        id: availableCol
        anchors.fill: parent
        anchors.topMargin: Style.marginM
        anchors.bottomMargin: Style.marginM
        anchors.leftMargin: showOnlyLists ? Style.marginL : 0
        anchors.rightMargin: showOnlyLists ? Style.marginL : 0
        spacing: Style.marginM

        RowLayout {
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
          spacing: Style.marginS

          NLabel {
            label: I18n.tr("wifi.panel.available-networks")
            Layout.fillWidth: true
          }
        }

        Repeater {
          model: root.availableNetworks
          delegate: nboxDelegate
        }

        // Add hidden network button
        NBox {
          visible: !root.showOnlyLists
          Layout.fillWidth: true
          Layout.preferredHeight: addHiddenContent.implicitHeight + Style.margin2M
          color: addHiddenMouseArea.containsMouse ? Color.mSurfaceVariant : Color.mSurface
          radius: Style.radiusM

          RowLayout {
            id: addHiddenContent
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginM

            NIcon {
              icon: "plus"
              pointSize: Style.fontSizeXXL
              color: Color.mOnSurfaceVariant
            }

            NText {
              text: I18n.tr("wifi.panel.add-hidden-network")
              pointSize: Style.fontSizeM
              color: Color.mOnSurface
              Layout.fillWidth: true
            }
          }

          MouseArea {
            id: addHiddenMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              addNetworkPopup.customSsid = "";
              addNetworkPopup.customPassword = "";
              addNetworkPopup.customSecurityKey = "wpa2-psk";
              addNetworkPopup.open();
            }
          }
        }
      }
    }

    Item {
      visible: !showOnlyLists
      Layout.fillWidth: true
    }

    // Airplane Mode
    NBox {
      id: miscSettingsBox
      visible: !root.showOnlyLists && Settings.data.network.wifiEnabled
      Layout.fillWidth: true
      Layout.preferredHeight: miscSettingsCol.implicitHeight + Style.margin2XL
      color: Color.mSurface

      ColumnLayout {
        id: miscSettingsCol
        anchors.fill: parent
        anchors.margins: Style.marginXL
        spacing: Style.marginM

        NToggle {
          label: I18n.tr("toast.airplane-mode.title")
          description: I18n.tr("toast.airplane-mode.description")
          icon: Settings.data.network.airplaneModeEnabled ? "plane" : "plane-off"
          checked: Settings.data.network.airplaneModeEnabled
          onToggled: checked => BluetoothService.setAirplaneMode(checked)
        }
      }
    }
  }

  // Add Hidden Network Popup
  Popup {
    id: addNetworkPopup
    visible: false
    anchors.centerIn: parent
    width: Math.min(parent.width * 0.9, 400 * Style.uiScaleRatio)
    height: addNetworkContent.implicitHeight + Style.margin2L
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    property string customSsid: ""
    property string customPassword: ""
    property string customIdentity: ""
    property string customSecurityKey: "wpa2-psk"

    onOpened: {
      customSsidInput.inputItem.forceActiveFocus();
    }

    // Make background transparent so we can use NDropShadow
    background: Item {}

    // Shadow effect (behind background)
    NDropShadow {
      anchors.fill: customPopupBg
      source: customPopupBg
      autoPaddingEnabled: true
      z: -1
    }

    Rectangle {
      id: customPopupBg
      anchors.fill: parent
      radius: Style.radiusL
      color: Qt.alpha(Color.mSurface, 0.95)
      border.color: Color.mOutline
      border.width: Style.borderS
    }

    ColumnLayout {
      id: addNetworkContent
      anchors.centerIn: parent
      width: parent.width - (Style.marginL * 2)
      spacing: Style.marginM

      // Header with Icon
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NImageRounded {
          Layout.preferredWidth: Style.fontSizeXXL * 2
          Layout.preferredHeight: Style.fontSizeXXL * 2
          fallbackIcon: "wifi"
          borderWidth: 0
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NText {
            text: I18n.tr("wifi.panel.add-hidden-network")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }
        }
      }

      // Input Fields
      NTextInput {
        id: customSsidInput
        Layout.fillWidth: true
        inputIconName: "wifi"
        placeholderText: I18n.tr("wifi.panel.network-name-ssid")
        label: I18n.tr("wifi.panel.network-name-ssid")
        text: addNetworkPopup.customSsid
        onTextChanged: addNetworkPopup.customSsid = text
        onAccepted: {
          if (addNetworkPopup.customSsid.length > 0 && (addNetworkPopup.customSecurityKey === "open" || addNetworkPopup.customPassword.length > 0)) {
            NetworkService.connectManual(addNetworkPopup.customSsid, addNetworkPopup.customPassword, addNetworkPopup.customSecurityKey, addNetworkPopup.customIdentity);
            addNetworkPopup.close();
          }
        }
      }

      NComboBox {
        Layout.fillWidth: true
        model: NetworkService.supportedSecurityTypes
        currentKey: addNetworkPopup.customSecurityKey
        onSelected: key => {
                      addNetworkPopup.customSecurityKey = key;
                    }
      }

      NTextInput {
        id: customIdentityInput
        Layout.fillWidth: true
        inputIconName: "user"
        visible: addNetworkPopup.customSecurityKey.indexOf("-eap") !== -1
        placeholderText: I18n.tr("wifi.enterprise.username")
        label: I18n.tr("wifi.enterprise.username")
        text: addNetworkPopup.customIdentity
        onTextChanged: addNetworkPopup.customIdentity = text
      }

      NTextInput {
        id: customPasswordInput
        Layout.fillWidth: true
        inputIconName: "key"
        visible: addNetworkPopup.customSecurityKey !== "open"
        placeholderText: I18n.tr("common.password")
        label: I18n.tr("common.password")
        text: addNetworkPopup.customPassword
        onTextChanged: addNetworkPopup.customPassword = text
        inputItem.echoMode: TextInput.Password
        onAccepted: {
          if (addNetworkPopup.customSsid.length > 0 && addNetworkPopup.customPassword.length > 0) {
            NetworkService.connectManual(addNetworkPopup.customSsid, addNetworkPopup.customPassword, addNetworkPopup.customSecurityKey, addNetworkPopup.customIdentity);
            addNetworkPopup.close();
          }
        }
      }

      // Actions
      RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginS
        spacing: Style.marginM

        Item {
          Layout.fillWidth: true
        } // Spacer

        NButton {
          text: I18n.tr("common.cancel")
          backgroundColor: Color.mSurfaceVariant
          textColor: Color.mOnSurfaceVariant
          outlined: false
          onClicked: addNetworkPopup.close()
        }

        NButton {
          text: I18n.tr("common.connect")
          backgroundColor: Color.mPrimary
          textColor: Color.mOnPrimary
          enabled: addNetworkPopup.customSsid.length > 0 && (addNetworkPopup.customSecurityKey === "open" || addNetworkPopup.customPassword.length > 0) && (addNetworkPopup.customSecurityKey.indexOf("-eap") === -1 || addNetworkPopup.customIdentity.length > 0)
          onClicked: {
            NetworkService.connectManual(addNetworkPopup.customSsid, addNetworkPopup.customPassword, addNetworkPopup.customSecurityKey, addNetworkPopup.customIdentity);
            addNetworkPopup.close();
          }
        }
      }
    }
  }

  // Shared Delegate
  Component {
    id: nboxDelegate
    NBox {
      id: networkItem

      readonly property bool isBusy: NetworkService.connectingTo === modelData.ssid || NetworkService.disconnectingFrom === modelData.ssid || NetworkService.forgettingNetwork === modelData.ssid
      readonly property bool isExpanded: root.infoSsid === modelData.ssid
      readonly property bool isEnterprise: NetworkService.isEnterprise(modelData.security)

      function getContentColor(defaultColor = Color.mOnSurface) {
        if (root.passwordSsid === modelData.ssid || NetworkService.connectingTo === modelData.ssid) {
          return Color.mPrimary;
        }
        if (NetworkService.disconnectingFrom === modelData.ssid || NetworkService.forgettingNetwork === modelData.ssid) {
          return Color.mError;
        }
        return defaultColor;
      }

      Layout.fillWidth: true
      Layout.preferredHeight: deviceColumn.implicitHeight + (Style.marginXL)
      radius: Style.radiusM
      clip: true

      color: (modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid) ? Qt.alpha(Color.mPrimary, Math.min(1.15 - Settings.data.ui.panelBackgroundOpacity, 0.75)) : Color.mSurface

      ColumnLayout {
        id: deviceColumn
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginS

        RowLayout {
          id: deviceLayout
          Layout.fillWidth: true
          spacing: Style.marginM
          Layout.alignment: Qt.AlignVCenter

          NIcon {
            icon: NetworkService.signalIcon(modelData.signal, modelData.connected)
            pointSize: Style.fontSizeXXL
            color: modelData.connected ? (NetworkService.internetConnectivity ? Color.mPrimary : Color.mError) : networkItem.getContentColor(Color.mOnSurface)
            Layout.alignment: Qt.AlignVCenter

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: TooltipService.show(parent, NetworkService.getSignalStrengthLabel(modelData.signal) + " (" + modelData.signal + "%)")
              onExited: TooltipService.hide()
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXXS

            NText {
              text: modelData.ssid
              pointSize: Style.fontSizeM
              font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
              elide: Text.ElideRight
              color: networkItem.getContentColor(Color.mOnSurface)
              Layout.fillWidth: true
            }

            RowLayout {
              spacing: Style.marginXS

              NIcon {
                icon: NetworkService.isSecured(modelData.security) ? "lock" : "lock-open"
                pointSize: Style.fontSizeXXS
                color: networkItem.getContentColor(Color.mOnSurfaceVariant)
                visible: !modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid && NetworkService.forgettingNetwork !== modelData.ssid
              }

              NText {
                text: {
                  if (NetworkService.disconnectingFrom === modelData.ssid) {
                    return I18n.tr("wifi.panel.disconnecting");
                  }
                  if (NetworkService.forgettingNetwork === modelData.ssid) {
                    return I18n.tr("wifi.panel.forgetting");
                  }
                  if (modelData.connected) {
                    switch (NetworkService.networkConnectivity) {
                    case "full":
                      return I18n.tr("common.connected");
                    case "limited":
                      return I18n.tr("wifi.panel.internet-limited");
                    case "portal":
                      return I18n.tr("wifi.panel.action-required");
                    default:
                      return NetworkService.networkConnectivity;
                    }
                  }
                  if (modelData.cached && !modelData.existing) {
                    return I18n.tr("wifi.panel.saved");
                  }
                  return NetworkService.isSecured(modelData.security) ? modelData.security : "Open";
                }
                pointSize: Style.fontSizeXXS
                color: networkItem.getContentColor(Color.mOnSurfaceVariant)
              }

              // Network speed indicators (visible when connected and speed > 0)
              RowLayout {
                visible: modelData.connected && (SystemStatService.rxSpeed > 0 || SystemStatService.txSpeed > 0)
                spacing: 2
                Layout.leftMargin: Style.marginXS

                NIcon {
                  visible: SystemStatService.rxSpeed > 0
                  icon: "arrow-down"
                  pointSize: Style.fontSizeXXS
                  color: networkItem.getContentColor(Color.mOnSurfaceVariant)
                }

                NText {
                  visible: SystemStatService.rxSpeed > 0
                  text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
                  pointSize: Style.fontSizeXXS
                  color: networkItem.getContentColor(Color.mOnSurfaceVariant)
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
                  color: networkItem.getContentColor(Color.mOnSurfaceVariant)
                }

                NText {
                  visible: SystemStatService.txSpeed > 0
                  text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
                  pointSize: Style.fontSizeXXS
                  color: networkItem.getContentColor(Color.mOnSurfaceVariant)
                }
              }
            }
          }

          Item {
            Layout.fillWidth: true
          }

          RowLayout {
            spacing: Style.marginS

            NBusyIndicator {
              visible: networkItem.isBusy
              running: visible
              color: Color.mPrimary
              size: Style.baseWidgetSize * 0.5
            }

            NIconButton {
              visible: modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid
              icon: "info"
              tooltipText: I18n.tr("common.info")
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
              visible: !root.showOnlyLists && (modelData.existing || modelData.cached) && !modelData.connected && !networkItem.isBusy
              icon: "trash"
              tooltipText: I18n.tr("tooltips.forget-network")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.requestForget(modelData.ssid)
            }

            NButton {
              id: button
              visible: !modelData.connected && NetworkService.connectingTo !== modelData.ssid && root.passwordSsid !== modelData.ssid
              enabled: !NetworkService.connecting && !networkItem.isBusy
              outlined: !button.hovered
              fontSize: Style.fontSizeS
              backgroundColor: Color.mPrimary
              text: I18n.tr("common.connect")
              onClicked: {
                if (modelData.existing || modelData.cached || !NetworkService.isSecured(modelData.security)) {
                  NetworkService.connect(modelData.ssid);
                } else {
                  root.requestPassword(modelData.ssid);
                }
              }
            }

            NButton {
              id: disconnectButton
              visible: modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid
              text: I18n.tr("common.disconnect")
              outlined: !disconnectButton.hovered
              fontSize: Style.fontSizeS
              backgroundColor: Color.mError
              onClicked: NetworkService.disconnect(modelData.ssid)
            }
          }
        }

        // Connection info details
        Rectangle {
          visible: networkItem.isExpanded
          Layout.fillWidth: true
          implicitHeight: infoColumn.implicitHeight + Style.margin2S
          radius: Style.radiusS
          color: Color.mSurfaceVariant
          border.width: Style.borderS
          border.color: Color.mOutline
          clip: true

          onVisibleChanged: {
            if (visible && infoColumn && infoColumn.forceLayout) {
              Qt.callLater(function () {
                infoColumn.forceLayout();
              });
            }
          }

          NIconButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Style.marginS
            icon: root.detailsGrid ? "layout-list" : "layout-grid"
            tooltipText: root.detailsGrid ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.detailsGrid = !root.detailsGrid;
              Settings.data.network.wifiDetailsViewMode = root.detailsGrid ? "grid" : "list";
            }
            z: 1
          }

          GridLayout {
            id: infoColumn
            anchors.fill: parent
            anchors.margins: Style.marginS
            columns: root.detailsGrid ? 2 : 1
            columnSpacing: Style.marginM
            rowSpacing: Style.marginXS
            onColumnsChanged: {
              if (infoColumn.forceLayout) {
                Qt.callLater(function () {
                  infoColumn.forceLayout();
                });
              }
            }

            // --- Item 1: Interface ---
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Style.marginXS
              Layout.row: 0
              Layout.column: 0
              NIcon {
                icon: "network"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
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
                wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                maximumLineCount: root.detailsGrid ? 1 : 6
                clip: true

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
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.bluetooth.address-copied"), "wifi");
                    }
                  }
                }
              }
            }
            // --- Item 2: Band & Channel & Width of channel ---
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.row: detailsGrid ? 1 : 1
              Layout.column: 0
              spacing: Style.marginXS
              NIcon {
                icon: "router"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
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
              }
            }
            // --- Item 3: Link Speed ---
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.row: detailsGrid ? 2 : 2
              Layout.column: 0
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
              }
            }
            // --- Item 4: IPv4 || IPv6 ---
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.row: detailsGrid ? 0 : 3
              Layout.column: detailsGrid ? 1 : 0
              spacing: Style.marginXS
              NIcon {
                icon: "network"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
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
                text: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.ipv4 || "-") : (NetworkService.activeWifiDetails.ipv6 || "-")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true

                MouseArea {
                  anchors.fill: parent
                  enabled: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.ipv4 && NetworkService.activeWifiDetails.ipv4.length > 0) : (NetworkService.activeWifiDetails.ipv6 && NetworkService.activeWifiDetails.ipv6.length > 0)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                  onExited: TooltipService.hide()
                  onClicked: {
                    const value = root.ipVersion === 4 ? (NetworkService.activeWifiDetails.ipv4 || "") : (NetworkService.activeWifiDetails.ipv6 || "");
                    if (value.length > 0) {
                      Quickshell.execDetached(["wl-copy", value]);
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.bluetooth.address-copied"), "wifi");
                    }
                  }
                }
              }
            }
            // --- Item 5: DNS ---
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.row: detailsGrid ? 1 : 4
              Layout.column: detailsGrid ? 1 : 0
              spacing: Style.marginXS
              NIcon {
                icon: "world"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
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
                text: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.dns4 || "-") : (NetworkService.activeWifiDetails.dns6 || "-")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true

                MouseArea {
                  anchors.fill: parent
                  enabled: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.dns4 && NetworkService.activeWifiDetails.dns4.length > 0) : (NetworkService.activeWifiDetails.dns6 && NetworkService.activeWifiDetails.dns6.length > 0)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                  onExited: TooltipService.hide()
                  onClicked: {
                    const value = root.ipVersion === 4 ? (NetworkService.activeWifiDetails.dns4 || "") : (NetworkService.activeWifiDetails.dns6 || "");
                    if (value.length > 0) {
                      Quickshell.execDetached(["wl-copy", value]);
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.bluetooth.address-copied"), "wifi");
                    }
                  }
                }
              }
            }
            // --- Item 6: Gateway ---
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              Layout.row: detailsGrid ? 2 : 5
              Layout.column: detailsGrid ? 1 : 0
              spacing: Style.marginXS
              NIcon {
                icon: "router"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
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
                text: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.gateway4 || "-") : (NetworkService.activeWifiDetails.gateway6 || "-")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true

                MouseArea {
                  anchors.fill: parent
                  enabled: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.gateway4 && NetworkService.activeWifiDetails.gateway4.length > 0) : (NetworkService.activeWifiDetails.gateway6 && NetworkService.activeWifiDetails.gateway6.length > 0)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                  onExited: TooltipService.hide()
                  onClicked: {
                    const value = root.ipVersion === 4 ? (NetworkService.activeWifiDetails.gateway4 || "") : (NetworkService.activeWifiDetails.gateway6 || "");
                    if (value.length > 0) {
                      Quickshell.execDetached(["wl-copy", value]);
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("toast.bluetooth.address-copied"), "wifi");
                    }
                  }
                }
              }
            }
          }
        }

        // Password input overlay-style within card
        Rectangle {
          visible: root.passwordSsid === modelData.ssid && !networkItem.isBusy
          Layout.fillWidth: true
          height: passwordLayout.implicitHeight + Style.margin2S
          color: Color.mSurfaceVariant
          border.color: Color.mOutline
          border.width: Style.borderS
          radius: Style.iRadiusXS

          ColumnLayout {
            id: passwordLayout
            anchors.fill: parent
            anchors.margins: Style.marginS
            spacing: Style.marginS

            // Inputs Container
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              // Identity field (Enterprise only)
              Rectangle {
                visible: networkItem.isEnterprise
                Layout.fillWidth: true
                Layout.preferredHeight: Style.baseWidgetSize * 0.9
                radius: Style.iRadiusXS
                color: Color.mSurface
                border.color: identityInput.activeFocus ? Color.mSecondary : Color.mOutline
                border.width: Style.borderS

                TextInput {
                  id: identityInput
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.marginS
                  font.family: Settings.data.ui.fontFixed
                  font.pointSize: Style.fontSizeS
                  color: Color.mOnSurface
                  selectByMouse: true
                  onVisibleChanged: {
                    if (visible) {
                      forceActiveFocus();
                    }
                  }
                  onAccepted: pwdInput.forceActiveFocus()

                  NText {
                    visible: parent.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("wifi.enterprise.username")
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                  }
                }
              }

              // Password field
              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.baseWidgetSize * 0.9
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
                  passwordCharacter: "●"
                  onVisibleChanged: {
                    if (visible && !networkItem.isEnterprise) {
                      forceActiveFocus();
                    }
                  }
                  onAccepted: {
                    if (text && !NetworkService.connecting) {
                      if (!networkItem.isEnterprise || identityInput.text.length > 0) {
                        root.submitPassword(modelData.ssid, text, identityInput.text);
                      }
                    }
                  }

                  NText {
                    visible: parent.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: networkItem.isEnterprise ? I18n.tr("wifi.enterprise.password") : I18n.tr("wifi.panel.enter-password")
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              Item {
                Layout.fillWidth: true
              }

              NButton {
                text: I18n.tr("common.connect")
                fontSize: Style.fontSizeS
                enabled: pwdInput.text.length > 0 && (!networkItem.isEnterprise || identityInput.text.length > 0) && !NetworkService.connecting
                outlined: true
                onClicked: root.submitPassword(modelData.ssid, pwdInput.text, identityInput.text)
              }

              NIconButton {
                icon: "close"
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: root.cancelPassword()
              }
            }
          }
        }

        // Forget network confirmation within card
        Rectangle {
          visible: root.expandedSsid === modelData.ssid && !networkItem.isBusy
          Layout.fillWidth: true
          height: forgetRow.implicitHeight + Style.margin2S
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
              outlined: !forgetButton.hovered
              onClicked: root.confirmForget(modelData.ssid)
            }

            NIconButton {
              icon: "close"
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.cancelForget()
            }
          }
        }
      }
    }
  }
}
