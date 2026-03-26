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
  property string enterpriseEap: "peap"
  property string enterprisePhase2: "mschapv2"
  property string enterpriseAnonIdentity: ""
  property string enterpriseCaCert: ""
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
    if (!NetworkService.wifiEnabled) {
      return [];
    }
    return activeNetworks.filter(n => n.connected).sort((a, b) => b.signal - a.signal);
  }

  readonly property var savedNetworks: {
    if (!NetworkService.wifiEnabled) {
      return [];
    }
    return activeNetworks.filter(n => !n.connected && n.existing).sort((a, b) => b.signal - a.signal);
  }

  readonly property var availableNetworks: {
    if (!NetworkService.wifiEnabled) {
      return [];
    }
    return activeNetworks.filter(n => !n.connected && !n.existing).sort((a, b) => b.signal - a.signal);
  }

  // Combined visibility check: tab must be visible AND the window must be visible
  readonly property bool effectivelyVisible: root.visible && Window.window && Window.window.visible

  onEffectivelyVisibleChanged: {
    if (effectivelyVisible) {
      SystemStatService.registerComponent("wifi-subtab");
      if (NetworkService.wifiEnabled && !NetworkService.scanningActive && !showOnlyLists) {
        NetworkService.scan();
        NetworkService.refreshActiveWifiDetails();
      }
    } else {
      SystemStatService.unregisterComponent("wifi-subtab");
    }
  }

  Component.onDestruction: {
    SystemStatService.unregisterComponent("wifi-subtab");
  }

  // Actions
  function requestPassword(ssid) {
    passwordSsid = ssid;
    identity = "";
    enterpriseEap = "peap";
    enterprisePhase2 = "mschapv2";
    enterpriseAnonIdentity = "";
    enterpriseCaCert = "";
    expandedSsid = "";
  }
  function submitPassword(ssid, password, identity = "") {
    NetworkService.connect(ssid, password, false, identity, {
                             eap: enterpriseEap,
                             phase2: enterprisePhase2,
                             anonIdentity: enterpriseAnonIdentity,
                             caCert: enterpriseCaCert
                           });
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
            icon: NetworkService.wifiEnabled ? "wifi" : "wifi-off"
            checked: NetworkService.wifiEnabled
            onToggled: checked => NetworkService.setWifiEnabled(checked)
            enabled: !NetworkService.airplaneModeEnabled && NetworkService.wifiAvailable
            Layout.alignment: Qt.AlignVCenter
          }
        }

        NDivider {
          Layout.fillWidth: true
          visible: NetworkService.wifiEnabled
        }

        NText {
          visible: !root.showOnlyLists && NetworkService.wifiEnabled
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
      visible: root.connectedNetworks.length > 0 && NetworkService.wifiEnabled
      Layout.fillWidth: true
      Layout.preferredHeight: connectedCol.implicitHeight + Style.margin2M
      border.color: showOnlyLists ? Style.boxBorderColor : "transparent"
      color: showOnlyLists ? Color.mSurfaceVariant : "transparent"

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
      visible: root.savedNetworks.length > 0 && NetworkService.wifiEnabled
      Layout.fillWidth: true
      Layout.preferredHeight: savedCol.implicitHeight + Style.margin2M
      border.color: showOnlyLists ? Style.boxBorderColor : "transparent"
      color: showOnlyLists ? Color.mSurfaceVariant : "transparent"

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
      visible: root.availableNetworks.length > 0 && NetworkService.wifiEnabled
      Layout.fillWidth: true
      Layout.preferredHeight: availableCol.implicitHeight + Style.margin2M
      border.color: showOnlyLists ? Style.boxBorderColor : "transparent"
      color: showOnlyLists ? Color.mSurfaceVariant : "transparent"

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
              text: I18n.tr("wifi.panel.add-network")
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
      visible: !showOnlyLists && NetworkService.wifiEnabled
      Layout.fillWidth: true
    }

    // Airplane Mode
    NBox {
      id: miscSettingsBox
      visible: !root.showOnlyLists && miscSettingsCol.visibleChildren.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: miscSettingsCol.implicitHeight + Style.margin2XL
      color: Color.mSurface

      ColumnLayout {
        id: miscSettingsCol
        anchors.fill: parent
        anchors.margins: Style.marginXL
        spacing: Style.marginM

        NToggle {
          visible: NetworkService.wifiAvailable && BluetoothService.bluetoothAvailable
          label: I18n.tr("toast.airplane-mode.title")
          description: I18n.tr("toast.airplane-mode.description")
          icon: NetworkService.airplaneModeEnabled ? "plane" : "plane-off"
          checked: NetworkService.airplaneModeEnabled
          onToggled: checked => NetworkService.setAirplaneMode(checked)
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
    property string customEnterpriseEap: "peap"
    property string customEnterprisePhase2: "mschapv2"
    property string customEnterpriseAnonIdentity: ""
    property string customEnterpriseCaCert: ""
    property bool customShowPassword: false
    property bool customIsHidden: false

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
            text: I18n.tr("wifi.panel.add-network")
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
        onEditingFinished: {
          if (addNetworkPopup.customSsid.length > 0 && (addNetworkPopup.customSecurityKey === "open" || addNetworkPopup.customPassword.length > 0)) {
            NetworkService.connect(addNetworkPopup.customSsid, addNetworkPopup.customPassword, addNetworkPopup.customIsHidden, addNetworkPopup.customSecurityKey, addNetworkPopup.customIdentity, {
                                     eap: addNetworkPopup.customEnterpriseEap,
                                     phase2: addNetworkPopup.customEnterprisePhase2,
                                     anonIdentity: addNetworkPopup.customEnterpriseAnonIdentity,
                                     caCert: addNetworkPopup.customEnterpriseCaCert
                                   });
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

      ColumnLayout {
        visible: addNetworkPopup.customSecurityKey.indexOf("-eap") !== -1
        Layout.fillWidth: true
        spacing: Style.marginM

        NComboBox {
          Layout.fillWidth: true
          label: I18n.tr("wifi.enterprise.eap-method")
          model: [
            {
              key: "peap",
              name: "PEAP"
            },
            {
              key: "ttls",
              name: "TTLS"
            }
          ]
          currentKey: addNetworkPopup.customEnterpriseEap
          onSelected: key => addNetworkPopup.customEnterpriseEap = key
        }

        NComboBox {
          Layout.fillWidth: true
          label: I18n.tr("wifi.enterprise.phase2-auth")
          model: [
            {
              key: "mschapv2",
              name: "MSCHAPv2"
            },
            {
              key: "pap",
              name: "PAP"
            },
            {
              key: "mschap",
              name: "MSCHAP"
            },
            {
              key: "chap",
              name: "CHAP"
            }
          ]
          currentKey: addNetworkPopup.customEnterprisePhase2
          onSelected: key => addNetworkPopup.customEnterprisePhase2 = key
        }
      }

      NTextInput {
        id: customAnonIdentityInput
        Layout.fillWidth: true
        inputIconName: "user-question"
        visible: addNetworkPopup.customSecurityKey.indexOf("-eap") !== -1
        placeholderText: I18n.tr("wifi.enterprise.anonymous-identity")
        label: I18n.tr("wifi.enterprise.anonymous-identity")
        text: addNetworkPopup.customEnterpriseAnonIdentity
        onTextChanged: addNetworkPopup.customEnterpriseAnonIdentity = text
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM
        visible: addNetworkPopup.customSecurityKey.indexOf("-eap") !== -1

        NTextInput {
          id: customCaCertInput
          Layout.fillWidth: true
          inputIconName: "certificate"
          placeholderText: I18n.tr("wifi.enterprise.ca-cert")
          label: I18n.tr("wifi.enterprise.ca-cert")
          text: addNetworkPopup.customEnterpriseCaCert
          onTextChanged: addNetworkPopup.customEnterpriseCaCert = text
        }

        NIconButton {
          icon: "folder-open"
          Layout.alignment: Qt.AlignBottom
          onClicked: caCertPicker.openForAddNetwork()
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
        inputItem.echoMode: addNetworkPopup.customShowPassword ? TextInput.Normal : TextInput.Password
        onEditingFinished: {
          if (addNetworkPopup.customSsid.length > 0 && addNetworkPopup.customPassword.length > 0) {
            NetworkService.connect(addNetworkPopup.customSsid, addNetworkPopup.customPassword, addNetworkPopup.customIsHidden, addNetworkPopup.customSecurityKey, addNetworkPopup.customIdentity, {
                                     eap: addNetworkPopup.customEnterpriseEap,
                                     phase2: addNetworkPopup.customEnterprisePhase2,
                                     anonIdentity: addNetworkPopup.customEnterpriseAnonIdentity,
                                     caCert: addNetworkPopup.customEnterpriseCaCert
                                   });
            addNetworkPopup.close();
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NCheckbox {
          Layout.fillWidth: true
          label: I18n.tr("wifi.panel.show-password")
          checked: addNetworkPopup.customShowPassword
          onToggled: checked => addNetworkPopup.customShowPassword = checked
          visible: addNetworkPopup.customSecurityKey !== "open"
        }

        NCheckbox {
          Layout.fillWidth: true
          label: I18n.tr("wifi.panel.hidden-network")
          checked: addNetworkPopup.customIsHidden
          onToggled: checked => addNetworkPopup.customIsHidden = checked
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
            NetworkService.connect(addNetworkPopup.customSsid, addNetworkPopup.customPassword, addNetworkPopup.customIsHidden, addNetworkPopup.customSecurityKey, addNetworkPopup.customIdentity, {
                                     eap: addNetworkPopup.customEnterpriseEap,
                                     phase2: addNetworkPopup.customEnterprisePhase2,
                                     anonIdentity: addNetworkPopup.customEnterpriseAnonIdentity,
                                     caCert: addNetworkPopup.customEnterpriseCaCert
                                   });
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

      function getContentColors(defaultColors = [Color.mSurface, Color.mOnSurface]) {
        if (root.passwordSsid === modelData.ssid || NetworkService.connectingTo === modelData.ssid) {
          return [Color.mPrimary, Color.mOnPrimary];
        }
        if (modelData.connected && NetworkService.internetConnectivity && NetworkService.disconnectingFrom !== modelData.ssid) {
          return [Color.mPrimary, Color.mOnPrimary];
        }
        if (NetworkService.disconnectingFrom === modelData.ssid || NetworkService.forgettingNetwork === modelData.ssid) {
          return [Color.mError, Color.mOnError];
        }
        if (modelData.connected && !NetworkService.internetConnectivity) {
          return [Color.mError, Color.mOnError];
        }
        return defaultColors;
      }

      Layout.fillWidth: true
      Layout.preferredHeight: deviceColumn.implicitHeight + (Style.marginXL)
      radius: Style.radiusM
      clip: true
      forceOpaque: true
      color: networkItem.getContentColors()[0]

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
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            horizontalAlignment: Text.AlignLeft
            icon: NetworkService.getSignalInfo(modelData.signal, modelData.connected).icon
            pointSize: Style.fontSizeXXL
            color: networkItem.getContentColors()[1]

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: TooltipService.show(parent, NetworkService.getSignalInfo(modelData.signal, modelData.connected).label + " (" + modelData.signal + "%)")
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
              color: networkItem.getContentColors()[1]
              Layout.fillWidth: true
            }

            RowLayout {
              spacing: Style.marginXS

              NIcon {
                icon: NetworkService.isSecured(modelData.security) ? "lock" : "lock-open"
                pointSize: Style.fontSizeXXS
                color: Qt.alpha(networkItem.getContentColors()[1], Style.opacityHeavy)
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
                  return NetworkService.isSecured(modelData.security) ? modelData.security : I18n.tr("wifi.panel.security-open");
                }
                pointSize: Style.fontSizeXXS
                color: Qt.alpha(networkItem.getContentColors()[1], Style.opacityHeavy)
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
                  color: Qt.alpha(networkItem.getContentColors()[1], Style.opacityHeavy)
                }

                NText {
                  visible: SystemStatService.rxSpeed > 0
                  text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
                  pointSize: Style.fontSizeXXS
                  color: Qt.alpha(networkItem.getContentColors()[1], Style.opacityHeavy)
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
                  color: Qt.alpha(networkItem.getContentColors()[1], Style.opacityHeavy)
                }

                NText {
                  visible: SystemStatService.txSpeed > 0
                  text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
                  pointSize: Style.fontSizeXXS
                  color: Qt.alpha(networkItem.getContentColors()[1], Style.opacityHeavy)
                  elide: Text.ElideNone
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
              running: visible && root.effectivelyVisible
              color: networkItem.getContentColors()[1]
              size: Style.baseWidgetSize * 0.5
            }

            NIconButton {
              visible: modelData.connected && NetworkService.disconnectingFrom !== modelData.ssid
              icon: "info"
              tooltipText: I18n.tr("common.info")
              baseSize: Style.baseWidgetSize * 0.75
              colorBg: Color.mSurfaceVariant
              colorFg: Color.mOnSurface
              colorBorder: "transparent"
              colorBorderHover: "transparent"
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
              visible: !root.showOnlyLists && modelData.existing && !modelData.connected && !networkItem.isBusy
              icon: "trash"
              tooltipText: I18n.tr("tooltips.forget-network")
              baseSize: Style.baseWidgetSize * 0.75
              colorBg: Color.mPrimary
              colorFg: Color.mOnPrimary
              colorBorder: "transparent"
              colorBorderHover: "transparent"
              onClicked: root.requestForget(modelData.ssid)
            }

            NButton {
              id: button
              visible: !modelData.connected && NetworkService.connectingTo !== modelData.ssid && root.passwordSsid !== modelData.ssid
              enabled: !NetworkService.connecting && !networkItem.isBusy
              fontSize: Style.fontSizeS
              backgroundColor: Color.mPrimary
              textColor: Color.mOnPrimary
              text: I18n.tr("common.connect")
              onClicked: {
                if (modelData.existing || !NetworkService.isSecured(modelData.security)) {
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
              fontSize: Style.fontSizeS
              backgroundColor: Color.mSurfaceVariant
              textColor: Color.mOnSurface
              onClicked: NetworkService.disconnect(modelData.ssid)
            }
          }
        }

        // Connection info details
        Rectangle {
          visible: networkItem.isExpanded
          Layout.fillWidth: true
          implicitHeight: infoColumn.implicitHeight + Style.margin2S
          radius: Style.radiusXS
          color: Color.mSurfaceVariant
          border.width: Style.borderS
          border.color: Style.boxBorderColor
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
            baseSize: Style.baseWidgetSize * 0.65
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
            flow: root.detailsGrid ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: root.detailsGrid ? 3 : 6
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
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.copied-to-clipboard"), "wifi");
                    }
                  }
                }
              }
            }
            // --- Item 2: Band & Channel & Width of channel ---
            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
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
                text: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.ipv4 || "-") : ((NetworkService.activeWifiDetails.ipv6 || []).join(", ") || "-")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true

                MouseArea {
                  anchors.fill: parent
                  enabled: root.ipVersion === 4 ? !!(NetworkService.activeWifiDetails.ipv4 && NetworkService.activeWifiDetails.ipv4.length > 0) : !!(NetworkService.activeWifiDetails.ipv6 && NetworkService.activeWifiDetails.ipv6.length > 0)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                  onExited: TooltipService.hide()
                  onClicked: {
                    const value = root.ipVersion === 4 ? (NetworkService.activeWifiDetails.ipv4 || "") : ((NetworkService.activeWifiDetails.ipv6 || []).join(", ") || "");
                    if (value.length > 0) {
                      Quickshell.execDetached(["wl-copy", value]);
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.copied-to-clipboard"), "wifi");
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
                text: root.ipVersion === 4 ? ((NetworkService.activeWifiDetails.dns4 || []).join(", ") || "-") : ((NetworkService.activeWifiDetails.dns6 || []).join(", ") || "-")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true

                MouseArea {
                  anchors.fill: parent
                  enabled: root.ipVersion === 4 ? !!(NetworkService.activeWifiDetails.dns4 && NetworkService.activeWifiDetails.dns4.length > 0) : !!(NetworkService.activeWifiDetails.dns6 && NetworkService.activeWifiDetails.dns6.length > 0)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                  onExited: TooltipService.hide()
                  onClicked: {
                    const value = root.ipVersion === 4 ? ((NetworkService.activeWifiDetails.dns4 || []).join(", ") || "") : ((NetworkService.activeWifiDetails.dns6 || []).join(", ") || "");
                    if (value.length > 0) {
                      Quickshell.execDetached(["wl-copy", value]);
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.copied-to-clipboard"), "wifi");
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
                text: root.ipVersion === 4 ? (NetworkService.activeWifiDetails.gateway4 || "-") : ((NetworkService.activeWifiDetails.gateway6 || []).join(", ") || "-")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true

                MouseArea {
                  anchors.fill: parent
                  enabled: root.ipVersion === 4 ? !!(NetworkService.activeWifiDetails.gateway4 && NetworkService.activeWifiDetails.gateway4.length > 0) : !!(NetworkService.activeWifiDetails.gateway6 && NetworkService.activeWifiDetails.gateway6.length > 0)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                  onExited: TooltipService.hide()
                  onClicked: {
                    const value = root.ipVersion === 4 ? (NetworkService.activeWifiDetails.gateway4 || "") : ((NetworkService.activeWifiDetails.gateway6 || []).join(", ") || "");
                    if (value.length > 0) {
                      Quickshell.execDetached(["wl-copy", value]);
                      ToastService.showNotice(I18n.tr("common.wifi"), I18n.tr("common.copied-to-clipboard"), "wifi");
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

              // Enterprise Configuration
              ColumnLayout {
                visible: networkItem.isEnterprise
                Layout.fillWidth: true
                spacing: Style.marginS

                NComboBox {
                  Layout.fillWidth: true
                  label: I18n.tr("wifi.enterprise.eap-method")
                  model: [
                    {
                      key: "peap",
                      name: "PEAP"
                    },
                    {
                      key: "ttls",
                      name: "TTLS"
                    }
                  ]
                  currentKey: root.enterpriseEap
                  onSelected: key => root.enterpriseEap = key
                }

                NComboBox {
                  Layout.fillWidth: true
                  label: I18n.tr("wifi.enterprise.phase2-auth")
                  model: [
                    {
                      key: "mschapv2",
                      name: "MSCHAPv2"
                    },
                    {
                      key: "pap",
                      name: "PAP"
                    },
                    {
                      key: "mschap",
                      name: "MSCHAP"
                    },
                    {
                      key: "chap",
                      name: "CHAP"
                    }
                  ]
                  currentKey: root.enterprisePhase2
                  onSelected: key => root.enterprisePhase2 = key
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Style.baseWidgetSize * 0.9
                    radius: Style.iRadiusXS
                    color: Color.mSurface
                    border.color: caCertInput.activeFocus ? Color.mSecondary : Color.mOutline
                    border.width: Style.borderS

                    TextInput {
                      id: caCertInput
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.margins: Style.marginS
                      font.family: Settings.data.ui.fontFixed
                      font.pointSize: Style.fontSizeS
                      color: Color.mOnSurface
                      selectByMouse: true
                      text: root.enterpriseCaCert
                      onTextChanged: root.enterpriseCaCert = text

                      NText {
                        visible: parent.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("wifi.enterprise.ca-cert")
                        color: Color.mOnSurfaceVariant
                        pointSize: Style.fontSizeS
                      }
                    }
                  }

                  NIconButton {
                    icon: "folder-open"
                    baseSize: Style.baseWidgetSize * 0.75
                    onClicked: caCertPicker.openForInline()
                  }
                }
              }

              // Anonymous Identity field (Enterprise only)
              Rectangle {
                visible: networkItem.isEnterprise
                Layout.fillWidth: true
                Layout.preferredHeight: Style.baseWidgetSize * 0.9
                radius: Style.iRadiusXS
                color: Color.mSurface
                border.color: anonIdentityInput.activeFocus ? Color.mSecondary : Color.mOutline
                border.width: Style.borderS

                TextInput {
                  id: anonIdentityInput
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.marginS
                  font.family: Settings.data.ui.fontFixed
                  font.pointSize: Style.fontSizeS
                  color: Color.mOnSurface
                  selectByMouse: true
                  text: root.enterpriseAnonIdentity
                  onTextChanged: root.enterpriseAnonIdentity = text
                  onEditingFinished: identityInput.forceActiveFocus()

                  NText {
                    visible: parent.text.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("wifi.enterprise.anonymous-identity")
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeS
                  }
                }
              }

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
                  onEditingFinished: pwdInput.forceActiveFocus()

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
                  onEditingFinished: {
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
                baseSize: Style.baseWidgetSize * 0.75
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
              baseSize: Style.baseWidgetSize * 0.75
              onClicked: root.cancelForget()
            }
          }
        }
      }
    }
  }

  NFilePicker {
    id: caCertPicker
    title: I18n.tr("wifi.enterprise.ca-cert")
    nameFilters: ["*.pem", "*.crt", "*.cer", "*.der", "*"]

    property bool isForAddNetwork: false

    function openForInline() {
      isForAddNetwork = false;
      openFilePicker();
    }

    function openForAddNetwork() {
      isForAddNetwork = true;
      openFilePicker();
    }

    onAccepted: paths => {
                  if (paths.length > 0) {
                    if (isForAddNetwork) {
                      addNetworkPopup.customEnterpriseCaCert = paths[0];
                    } else {
                      root.enterpriseCaCert = paths[0];
                    }
                  }
                }
  }
}
