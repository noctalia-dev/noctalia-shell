import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Services.Networking
import qs.Widgets

Item {
  id: root
  Layout.fillWidth: true
  implicitHeight: mainLayout.implicitHeight

  property string expandedUuid: ""

  ColumnLayout {
    id: mainLayout
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.marginL

    // Add VPN buttons
    NBox {
      Layout.fillWidth: true
      Layout.preferredHeight: addVpnCol.implicitHeight + Style.margin2L
      color: Color.mSurface

      ColumnLayout {
        id: addVpnCol
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        NLabel {
          label: I18n.tr("panels.connections.vpn-add-title")
          Layout.fillWidth: true
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM

          NButton {
            text: I18n.tr("panels.connections.vpn-add-wireguard")
            icon: "plus"
            outlined: true
            enabled: !VPNService.importing
            onClicked: wgFilePicker.openFilePicker()
          }

          NButton {
            text: I18n.tr("panels.connections.vpn-add-openvpn")
            icon: "plus"
            outlined: true
            enabled: !VPNService.importing
            onClicked: ovpnFilePicker.openFilePicker()
          }
        }

        NText {
          visible: VPNService.importing
          text: I18n.tr("panels.connections.vpn-importing")
          pointSize: Style.fontSizeS
          color: Color.mPrimary
          Layout.fillWidth: true
        }
      }
    }

    // Active VPN Connections
    NBox {
      visible: VPNService.activeConnections.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: activeVpnCol.implicitHeight + Style.margin2M

      ColumnLayout {
        id: activeVpnCol
        anchors.fill: parent
        anchors.topMargin: Style.marginM
        anchors.bottomMargin: Style.marginM
        spacing: Style.marginM

        NLabel {
          label: I18n.tr("panels.connections.vpn-active")
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
        }

        Repeater {
          model: VPNService.activeConnections
          delegate: vpnDelegate
        }
      }
    }

    // Inactive VPN Connections
    NBox {
      visible: VPNService.inactiveConnections.length > 0
      Layout.fillWidth: true
      Layout.preferredHeight: inactiveVpnCol.implicitHeight + Style.margin2M

      ColumnLayout {
        id: inactiveVpnCol
        anchors.fill: parent
        anchors.topMargin: Style.marginM
        anchors.bottomMargin: Style.marginM
        spacing: Style.marginM

        NLabel {
          label: I18n.tr("panels.connections.vpn-available")
          Layout.fillWidth: true
          Layout.leftMargin: Style.marginS
        }

        Repeater {
          model: VPNService.inactiveConnections
          delegate: vpnDelegate
        }
      }
    }

    // Empty state
    NBox {
      visible: VPNService.initialLoadDone && Object.keys(VPNService.connections).length === 0
      Layout.fillWidth: true
      Layout.preferredHeight: emptyCol.implicitHeight + Style.margin2L
      color: Color.mSurface

      ColumnLayout {
        id: emptyCol
        anchors.fill: parent
        anchors.margins: Style.marginL
        spacing: Style.marginM

        NIcon {
          icon: "shield-off"
          pointSize: Style.fontSizeXXL * 2
          color: Color.mOnSurfaceVariant
          Layout.alignment: Qt.AlignHCenter
        }

        NText {
          text: I18n.tr("panels.connections.vpn-empty")
          pointSize: Style.fontSizeM
          color: Color.mOnSurfaceVariant
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        NText {
          text: I18n.tr("panels.connections.vpn-empty-hint")
          pointSize: Style.fontSizeS
          color: Color.mOnSurfaceVariant
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }
      }
    }
  }

  // VPN Connection Delegate
  Component {
    id: vpnDelegate
    NBox {
      id: vpnItem

      readonly property bool isExpanded: root.expandedUuid === modelData.uuid
      readonly property bool isBusy: (VPNService.connecting && VPNService.connectingUuid === modelData.uuid) || (VPNService.disconnecting && VPNService.disconnectingUuid === modelData.uuid)

      Layout.fillWidth: true
      Layout.preferredHeight: vpnColumn.implicitHeight + Style.marginXL
      radius: Style.radiusM
      clip: true
      color: modelData.active ? Qt.alpha(Color.mPrimary, 0.15) : Color.mSurface

      ColumnLayout {
        id: vpnColumn
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginS

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginM
          Layout.alignment: Qt.AlignVCenter

          NIcon {
            icon: modelData.active ? "shield-lock" : "shield"
            pointSize: Style.fontSizeXXL
            color: modelData.active ? Color.mPrimary : Color.mOnSurface
            Layout.alignment: Qt.AlignVCenter
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginXXS

            NText {
              text: modelData.name
              pointSize: Style.fontSizeM
              font.weight: modelData.active ? Style.fontWeightBold : Style.fontWeightMedium
              elide: Text.ElideRight
              color: Color.mOnSurface
              Layout.fillWidth: true
            }

            NText {
              text: {
                if (vpnItem.isBusy) {
                  return modelData.active ? I18n.tr("common.disconnecting") : I18n.tr("common.connecting");
                }
                var typeName = modelData.type === "wireguard" ? "WireGuard" : "OpenVPN";
                return modelData.active ? I18n.tr("panels.connections.vpn-connected-type", {
                                                    "type": typeName
                                                  }) : typeName;
              }
              pointSize: Style.fontSizeXS
              color: modelData.active ? Color.mPrimary : Color.mOnSurfaceVariant
            }
          }

          Item {
            Layout.fillWidth: true
          }

          RowLayout {
            spacing: Style.marginS

            NIconButton {
              icon: "info"
              tooltipText: I18n.tr("common.info")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: root.expandedUuid = (root.expandedUuid === modelData.uuid) ? "" : modelData.uuid
            }

            NIconButton {
              visible: !modelData.active
              icon: "trash"
              tooltipText: I18n.tr("panels.connections.vpn-delete")
              baseSize: Style.baseWidgetSize * 0.8
              enabled: !VPNService.deleting
              onClicked: VPNService.deleteConnection(modelData.uuid)
            }

            NButton {
              enabled: !vpnItem.isBusy
              outlined: !hovered
              fontSize: Style.fontSizeS
              backgroundColor: modelData.active ? Color.mError : Color.mPrimary
              text: modelData.active ? I18n.tr("common.disconnect") : I18n.tr("common.connect")
              icon: vpnItem.isBusy ? "busy" : null
              onClicked: VPNService.toggle(modelData.uuid)
            }
          }
        }

        // Expanded details
        Rectangle {
          visible: vpnItem.isExpanded
          Layout.fillWidth: true
          implicitHeight: detailsGrid.implicitHeight + Style.margin2S
          radius: Style.radiusS
          color: Color.mSurfaceVariant
          border.width: Style.borderS
          border.color: Color.mOutline
          clip: true

          GridLayout {
            id: detailsGrid
            anchors.fill: parent
            anchors.margins: Style.marginS
            columns: 2
            columnSpacing: Style.marginM
            rowSpacing: Style.marginXS

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Style.marginXS
              NIcon {
                icon: "shield"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: modelData.type === "wireguard" ? "WireGuard" : "OpenVPN"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.preferredWidth: 1
              spacing: Style.marginXS
              NIcon {
                icon: modelData.active ? "plug-connected" : "plug"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: modelData.active ? I18n.tr("common.connected") : I18n.tr("common.disconnected")
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }

            RowLayout {
              visible: modelData.active && modelData.device && modelData.device !== "--"
              Layout.fillWidth: true
              Layout.columnSpan: 2
              spacing: Style.marginXS
              NIcon {
                icon: "network"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: modelData.device || ""
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
              }
            }

            RowLayout {
              Layout.fillWidth: true
              Layout.columnSpan: 2
              spacing: Style.marginXS
              NIcon {
                icon: "hash"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
              }
              NText {
                text: modelData.uuid
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                Layout.fillWidth: true
                elide: Text.ElideMiddle
              }
            }
          }
        }
      }
    }
  }

  // File picker for WireGuard configs
  NFilePicker {
    id: wgFilePicker
    title: I18n.tr("panels.connections.vpn-select-wireguard")
    selectionMode: "files"
    nameFilters: ["*.conf"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    VPNService.importConnection(paths[0]);
                  }
                }
  }

  // File picker for OpenVPN configs
  NFilePicker {
    id: ovpnFilePicker
    title: I18n.tr("panels.connections.vpn-select-openvpn")
    selectionMode: "files"
    nameFilters: ["*.ovpn"]
    onAccepted: paths => {
                  if (paths.length > 0) {
                    VPNService.importConnection(paths[0]);
                  }
                }
  }
}
