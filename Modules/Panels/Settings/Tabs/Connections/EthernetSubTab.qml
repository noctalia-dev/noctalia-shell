import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell

import qs.Commons
import qs.Services.Networking
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Item {
  id: root
  Layout.fillWidth: true
  implicitHeight: mainLayout.implicitHeight

  NetworkEditPopup {
    id: networkEditPopup
    parent: Overlay.overlay
  }

  property string expandedIf: ""
  property int ipVersion: 4
  property bool detailsGrid: (Settings.data && Settings.data.network && Settings.data.network.wifiDetailsViewMode === "grid")

  readonly property bool effectivelyVisible: root.visible && Window.window && Window.window.visible

  onEffectivelyVisibleChanged: {
    if (effectivelyVisible) {
      SystemStatService.registerComponent("ethernet-subtab");
      if (NetworkService.ethernetConnected) {
        NetworkService.refreshActiveEthernetDetails();
      }
    } else {
      SystemStatService.unregisterComponent("ethernet-subtab");
    }
  }

  Component.onDestruction: {
    SystemStatService.unregisterComponent("ethernet-subtab");
  }

  ColumnLayout {
    id: mainLayout
    width: root.width
    spacing: Style.marginM

    // === Header ===
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: I18n.tr("wifi.panel.available-interfaces")
        pointSize: Style.fontSizeM
        font.weight: Style.fontWeightSemiBold
        color: Color.mOnSurface
        visible: NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0
      }
    }

    // === Empty state ===
    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
      Layout.preferredHeight: implicitHeight + Style.margin2L
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

    // === Interfaces list ===
    ColumnLayout {
      Layout.fillWidth: true
      visible: NetworkService.ethernetInterfaces && NetworkService.ethernetInterfaces.length > 0
      spacing: Style.marginXS

      Repeater {
        model: NetworkService.ethernetInterfaces || []
        delegate: ColumnLayout {
          id: ethDelegate
          Layout.fillWidth: true
          spacing: 0

          required property int index
          required property var modelData

          property bool isExpanded: root.expandedIf === modelData.ifname

          function getContentColors(defaultColors) {
            if (!defaultColors) defaultColors = [Color.mSurface, Color.mOnSurface];
            if (modelData.connected) {
              return [Color.mPrimary, Color.mOnPrimary];
            }
            return defaultColors;
          }

          // Interface card
          NBox {
            Layout.fillWidth: true
            implicitHeight: cardColumn.implicitHeight + Style.margin2M
            radius: Style.radiusM
            forceOpaque: true
            color: ethDelegate.getContentColors()[0]

            ColumnLayout {
              id: cardColumn
              width: parent.width - Style.margin2M
              x: Style.marginM
              y: Style.marginM
              spacing: Style.marginS

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NIcon {
                  Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                  icon: NetworkService.getIcon(true)
                  pointSize: Style.fontSizeXXL
                  color: ethDelegate.getContentColors()[1]
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  NText {
                    text: modelData.connectionName || modelData.ifname
                    pointSize: Style.fontSizeM
                    font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
                    color: ethDelegate.getContentColors()[1]
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
                      color: Qt.alpha(ethDelegate.getContentColors()[1], Style.opacityHeavy)
                    }

                    RowLayout {
                      visible: (modelData.connected && NetworkService.networkConnectivity === "full") && (SystemStatService.rxSpeed > 0 || SystemStatService.txSpeed > 0)
                      spacing: 2
                      Layout.leftMargin: Style.marginXS

                      NIcon {
                        visible: SystemStatService.rxSpeed > 0
                        icon: "arrow-down"
                        pointSize: Style.fontSizeXXS
                        color: Qt.alpha(ethDelegate.getContentColors()[1], Style.opacityHeavy)
                      }
                      NText {
                        visible: SystemStatService.rxSpeed > 0
                        text: SystemStatService.formatSpeed(SystemStatService.rxSpeed)
                        pointSize: Style.fontSizeXXS
                        color: Qt.alpha(ethDelegate.getContentColors()[1], Style.opacityHeavy)
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
                        color: Qt.alpha(ethDelegate.getContentColors()[1], Style.opacityHeavy)
                      }
                      NText {
                        visible: SystemStatService.txSpeed > 0
                        text: SystemStatService.formatSpeed(SystemStatService.txSpeed)
                        pointSize: Style.fontSizeXXS
                        color: Qt.alpha(ethDelegate.getContentColors()[1], Style.opacityHeavy)
                      }
                    }
                  }
                }

                // Info toggle
                NIconButton {
                  icon: "info"
                  tooltipText: I18n.tr("common.info")
                  baseSize: Style.baseWidgetSize * 0.75
                  colorBg: Color.mSurfaceVariant
                  colorFg: Color.mOnSurface
                  colorBorder: "transparent"
                  colorBorderHover: "transparent"
                  visible: modelData.connected
                  onClicked: {
                    if (ethDelegate.isExpanded) {
                      root.expandedIf = "";
                      return;
                    }
                    if (NetworkService.activeEthernetIf !== modelData.ifname) {
                      NetworkService.activeEthernetIf = modelData.ifname;
                      NetworkService.activeEthernetDetailsTimestamp = 0;
                    }
                    root.expandedIf = modelData.ifname;
                    NetworkService.refreshActiveEthernetDetails();
                  }
                }
              }
            }
          }

          // Connection info details
          Rectangle {
            visible: ethDelegate.isExpanded
            Layout.fillWidth: true
            implicitHeight: infoColumn.implicitHeight + Style.margin2S
            radius: Style.radiusXS
            color: Color.mSurfaceVariant
            border.width: Style.borderS
            border.color: Style.boxBorderColor
            clip: true

            onVisibleChanged: {
              if (visible && infoColumn && infoColumn.forceLayout) {
                Qt.callLater(function () { infoColumn.forceLayout(); });
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

            NIconButton {
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.rightMargin: Style.marginS + (Style.baseWidgetSize * 0.65) + Style.marginS
              anchors.topMargin: Style.marginS
              icon: "settings"
              tooltipText: I18n.tr("wifi.edit.title")
              baseSize: Style.baseWidgetSize * 0.65
              onClicked: {
                var connName = NetworkService.activeEthernetDetails.connectionName || "";
                if (connName) {
                  networkEditPopup.openEdit(connName, true, false);
                }
              }
              z: 1
            }

            GridLayout {
              id: infoColumn
              anchors.fill: parent
              anchors.margins: Style.marginS
              anchors.rightMargin: Style.baseWidgetSize
              flow: root.detailsGrid ? GridLayout.TopToBottom : GridLayout.LeftToRight
              rows: root.detailsGrid ? 3 : 6
              columns: root.detailsGrid ? 2 : 1
              columnSpacing: Style.marginM
              rowSpacing: Style.marginXS
              onColumnsChanged: {
                if (infoColumn.forceLayout) {
                  Qt.callLater(function () { infoColumn.forceLayout(); });
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
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
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

              // --- Item 2: Hardware Address ---
              RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: Style.marginXS
                NIcon {
                  icon: "hash"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
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
                  wrapMode: root.detailsGrid ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
                  elide: root.detailsGrid ? Text.ElideRight : Text.ElideNone
                  maximumLineCount: root.detailsGrid ? 1 : 6
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
                  text: root.ipVersion === 4 ? (NetworkService.activeEthernetDetails.ipv4 || "-") : ((NetworkService.activeEthernetDetails.ipv6 || []).join(", ") || "-")
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
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
