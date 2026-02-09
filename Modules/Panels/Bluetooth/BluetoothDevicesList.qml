import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import qs.Commons
import qs.Services.Hardware
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

NBox {
  id: root

  property string label: ""
  property string tooltipText: ""
  property var model: {}
  // Header control mode: "layout" (default) shows grid/list toggle; "filter" shows unnamed-devices filter toggle
  property string headerMode: "layout"
  // Per-list expanded details (by device key)
  property string expandedDeviceKey: ""
  // Local layout toggle for details: true = grid (2 cols), false = rows (1 col)
  // Persisted under Settings.data.network.bluetoothDetailsViewMode
  property bool detailsGrid: (Settings.data && Settings.data.ui && Settings.data.network.bluetoothDetailsViewMode !== undefined) ? (Settings.data.network.bluetoothDetailsViewMode === "grid") : true

  // Selection support
  property int selectedIndex: -1
  property bool isFocusedList: false
  property alias count: deviceList.count
  signal requestScrollToItem(var item, real topPadding)

  onSelectedIndexChanged: {
    if (selectedIndex >= 0 && isFocusedList) {
      // Find the item
      var item = deviceList.itemAt(selectedIndex);
      var topPadding = (selectedIndex === 0) ? (listHeader.height + column.spacing) : 0;
      if (item)
        requestScrollToItem(item, topPadding);
    }
  }

  onIsFocusedListChanged: {
    if (isFocusedList && selectedIndex >= 0) {
      var item = deviceList.itemAt(selectedIndex);
      var topPadding = (selectedIndex === 0) ? (listHeader.height + column.spacing) : 0;
      if (item)
        requestScrollToItem(item, topPadding);
    }
  }

  function getSelectedItem() {
    if (selectedIndex >= 0 && selectedIndex < count) {
      return root.model[selectedIndex];
    }
    return null;
  }

  // Reset selection when model changes significantly or visibility changes
  onVisibleChanged: {
    if (!visible)
      selectedIndex = -1;
  }

  Layout.fillWidth: true
  Layout.preferredHeight: column.implicitHeight + Style.marginXL

  ColumnLayout {
    id: column
    anchors.fill: parent
    anchors.margins: Style.marginM

    spacing: Style.marginM

    RowLayout {
      id: listHeader
      Layout.fillWidth: true
      visible: root.model.length > 0
      Layout.leftMargin: Style.marginM
      spacing: Style.marginS

      NText {
        text: root.label
        pointSize: Style.fontSizeS
        color: Color.mSecondary
        font.weight: Style.fontWeightBold
        Layout.fillWidth: true
      }

      // (moved) details view toggle is now inside the expanded info box

      // Filter toggle (for Available devices): hide unnamed devices
      NIconButton {
        visible: root.headerMode === "filter"
        // Option A: filter/filter-off
        // Off (show all): filter; On (hide unnamed): filter-off
        icon: (Settings.data && Settings.data.ui && Settings.data.network.bluetoothHideUnnamedDevices) ? "filter-off" : "filter"
        tooltipText: (Settings.data && Settings.data.ui && Settings.data.network.bluetoothHideUnnamedDevices) ? I18n.tr("tooltips.hide-unnamed-devices") : I18n.tr("tooltips.show-all-devices")
        onClicked: {
          if (Settings.data && Settings.data.ui) {
            Settings.data.network.bluetoothHideUnnamedDevices = !(Settings.data.network.bluetoothHideUnnamedDevices);
          }
        }
      }
    }

    Repeater {
      id: deviceList
      Layout.fillWidth: true
      model: root.model
      visible: BluetoothService.adapter && BluetoothService.adapter.enabled

      NBox {
        id: device

        readonly property bool canConnect: BluetoothService.canConnect(modelData)
        readonly property bool canDisconnect: BluetoothService.canDisconnect(modelData)
        readonly property bool canPair: BluetoothService.canPair(modelData)
        readonly property bool isBusy: BluetoothService.isDeviceBusy(modelData)
        readonly property bool isExpanded: root.expandedDeviceKey === BluetoothService.deviceKey(modelData)
        readonly property bool isSelected: root.isFocusedList && index === root.selectedIndex

        function getContentColor(defaultColor = Color.mOnSurface) {
          if (modelData.pairing || modelData.state === BluetoothDeviceState.Connecting)
            return Color.mPrimary;
          if (modelData.blocked || modelData.state === BluetoothDeviceState.Disconnecting)
            return Color.mError;
          return defaultColor;
        }

        Layout.fillWidth: true
        Layout.preferredHeight: deviceColumn.implicitHeight + (Style.marginXL)
        radius: Style.radiusM
        clip: true

        border.width: isSelected ? Style.borderM : 0
        border.color: Color.mPrimary

        color: (modelData.connected && modelData.state !== BluetoothDeviceState.Disconnecting) ? Qt.alpha(Color.mPrimary, 0.15) : Color.mSurface

        // Content column so expanded details are laid out inside the card
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

            // One device BT icon
            NIcon {
              icon: BluetoothService.getDeviceIcon(modelData)
              pointSize: Style.fontSizeXXL
              color: getContentColor(Color.mOnSurface)
              Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.marginXXS

              // Device name
              NText {
                text: modelData.name || modelData.deviceName
                pointSize: Style.fontSizeM
                font.weight: modelData.connected ? Style.fontWeightBold : Style.fontWeightMedium
                elide: Text.ElideRight
                color: getContentColor(Color.mOnSurface)
                Layout.fillWidth: true
              }

              // Status
              NText {
                text: {
                  const k = BluetoothService.getStatusKey(modelData);
                  if (k === "pairing")
                    return I18n.tr("common.pairing");
                  if (k === "blocked")
                    return I18n.tr("bluetooth.panel.blocked");
                  if (k === "connecting")
                    return I18n.tr("common.connecting");
                  if (k === "disconnecting")
                    return I18n.tr("common.disconnecting");
                  return "";
                }
                visible: text !== ""
                pointSize: Style.fontSizeXS
                color: getContentColor(Color.mOnSurfaceVariant)
              }

              // Signal strength: show only in the expanded info panel (hidden in compact row)
              RowLayout {
                visible: false
                Layout.fillWidth: true
                spacing: Style.marginXS
              }

              // Battery (icon + percent)
              RowLayout {
                visible: modelData.batteryAvailable
                spacing: Style.marginXS

                NIcon {
                  icon: {
                    var b = BluetoothService.getBatteryPercent(modelData);
                    return BatteryService.getIcon(b !== null ? b : 0, false, false, b !== null);
                  }
                  pointSize: Style.fontSizeXS
                  color: getContentColor(Color.mOnSurface)
                }

                NText {
                  text: {
                    var b = BluetoothService.getBatteryPercent(modelData);
                    return b === null ? "-" : (b + "%");
                  }
                  pointSize: Style.fontSizeXS
                  color: getContentColor(Color.mOnSurfaceVariant)
                }
              }
            }

            // Spacer to push actions to the right
            Item {
              Layout.fillWidth: true
            }

            // Actions (Info on the left to match Wi‑Fi, then Unpair, then main CTA)
            RowLayout {
              spacing: Style.marginS

              // Info for connected device (placed before the CTA for consistency with Wi‑Fi)
              NIconButton {
                visible: modelData.connected
                icon: "info"
                tooltipText: I18n.tr("common.info")
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: {
                  const key = BluetoothService.deviceKey(modelData);
                  root.expandedDeviceKey = (root.expandedDeviceKey === key) ? "" : key;
                }
              }

              // Unpair for saved devices when not connected
              NIconButton {
                visible: (modelData.paired || modelData.trusted) && !modelData.connected && !isBusy && !modelData.blocked
                icon: "trash"
                tooltipText: I18n.tr("common.unpair")
                baseSize: Style.baseWidgetSize * 0.8
                onClicked: BluetoothService.unpairDevice(modelData)
              }

              // Main Call to action
              NButton {
                id: button
                visible: (modelData.state !== BluetoothDeviceState.Connecting)
                enabled: (canConnect || canDisconnect || canPair) && !isBusy
                outlined: !button.hovered
                fontSize: Style.fontSizeS
                tooltipText: root.tooltipText
                text: {
                  if (modelData.pairing) {
                    return I18n.tr("common.pairing");
                  }
                  if (modelData.blocked) {
                    return I18n.tr("bluetooth.panel.blocked");
                  }
                  if (modelData.connected) {
                    return I18n.tr("common.disconnect");
                  }
                  if (device.canPair) {
                    return I18n.tr("common.pair");
                  }
                  return I18n.tr("common.connect");
                }
                icon: (isBusy ? "busy" : null)
                onClicked: {
                  if (modelData.connected) {
                    BluetoothService.disconnectDevice(modelData);
                  } else {
                    if (device.canPair) {
                      BluetoothService.pairDevice(modelData);
                    } else {
                      BluetoothService.connectDeviceWithTrust(modelData);
                    }
                  }
                }
              }
            }
          }

          // Expanded info section
          Rectangle {
            visible: device.isExpanded
            Layout.fillWidth: true
            implicitHeight: infoColumn.implicitHeight + Style.marginS * 2
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

            // Grid/List toggle moved here to the top-right corner of the info box
            NIconButton {
              id: detailsToggle
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.marginS
              // Use Tabler layout icons; "grid" alone doesn't exist in our font
              icon: root.detailsGrid ? "layout-list" : "layout-grid"
              tooltipText: root.detailsGrid ? I18n.tr("tooltips.list-view") : I18n.tr("tooltips.grid-view")
              baseSize: Style.baseWidgetSize * 0.8
              onClicked: {
                root.detailsGrid = !root.detailsGrid;
                if (Settings.data && Settings.data.ui) {
                  Settings.data.network.bluetoothDetailsViewMode = root.detailsGrid ? "grid" : "list";
                }
              }
              z: 1
            }

            GridLayout {
              id: infoColumn
              anchors.fill: parent
              anchors.margins: Style.marginS
              // Layout toggle based on local state
              columns: root.detailsGrid ? 2 : 1
              columnSpacing: Style.marginM
              rowSpacing: Style.marginXS
              // Ensure proper relayout when switching grid/list while open
              onColumnsChanged: {
                if (infoColumn.forceLayout) {
                  Qt.callLater(function () {
                    infoColumn.forceLayout();
                  });
                }
              }

              // Icons only; labels shown as tooltips on hover

              // Row 1: Signal | Battery
              RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: Style.marginXS
                NIcon {
                  icon: BluetoothService.getSignalIcon(modelData)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("common.signal"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: BluetoothService.getSignalStrength(modelData)
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  // Wrap only when needed to avoid extra spacing
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 4
                  clip: true
                }
              }
              RowLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: Style.marginXS
                NIcon {
                  icon: {
                    var b = BluetoothService.getBatteryPercent(modelData);
                    return BatteryService.getIcon(b !== null ? b : 0, false, false, b !== null);
                  }
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("common.battery"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: {
                    var b = BluetoothService.getBatteryPercent(modelData);
                    return b === null ? "-" : (b + "%");
                  }
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 4
                  clip: true
                }
              }

              // Row 2: Paired | Trusted
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: "link"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("common.paired"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: modelData.paired ? I18n.tr("common.yes") : I18n.tr("common.no")
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 2
                  clip: true
                }
              }
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginXS
                NIcon {
                  icon: "shield-check"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: TooltipService.show(parent, I18n.tr("common.trusted"))
                    onExited: TooltipService.hide()
                  }
                }
                NText {
                  text: modelData.trusted ? I18n.tr("common.yes") : I18n.tr("common.no")
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 2
                  clip: true
                }
              }

              // Row 3: Address (single row; spans two columns when grid)
              RowLayout {
                Layout.fillWidth: true
                Layout.columnSpan: infoColumn.columns === 2 ? 2 : 1
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
                  id: macAddressText
                  text: modelData.address || "-"
                  pointSize: Style.fontSizeXS
                  color: Color.mOnSurface
                  Layout.fillWidth: true
                  // MAC addresses usually fit; wrap only if necessary
                  wrapMode: implicitWidth > width ? Text.WrapAtWordBoundaryOrAnywhere : Text.NoWrap
                  elide: Text.ElideNone
                  maximumLineCount: 2
                  clip: true

                  // Click-to-copy MAC address
                  MouseArea {
                    anchors.fill: parent
                    enabled: (modelData.address && modelData.address.length > 0)
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: TooltipService.show(parent, I18n.tr("tooltips.copy-address"))
                    onExited: TooltipService.hide()
                    onClicked: {
                      const addr = modelData.address || "";
                      if (addr.length > 0) {
                        // Copy to clipboard via wl-copy (runtime dependency)
                        Quickshell.execDetached(["wl-copy", addr]);
                        ToastService.showNotice(I18n.tr("common.bluetooth"), I18n.tr("toast.bluetooth.address-copied"), "bluetooth");
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
