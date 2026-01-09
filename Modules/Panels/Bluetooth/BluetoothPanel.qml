import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Networking
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(500 * Style.uiScaleRatio)

  panelContent: Rectangle {
    id: panelContent
    color: "transparent"

    property real contentPreferredHeight: Math.min(root.preferredHeight, mainColumn.implicitHeight + Style.marginL * 2)

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
            icon: BluetoothService.enabled ? "bluetooth" : "bluetooth-off"
            pointSize: Style.fontSizeXXL
            color: BluetoothService.enabled ? Color.mPrimary : Color.mOnSurfaceVariant
          }

          NText {
            text: I18n.tr("common.bluetooth")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NToggle {
            id: bluetoothSwitch
            checked: BluetoothService.enabled
            onToggled: checked => BluetoothService.setBluetoothEnabled(checked)
            baseSize: Style.baseWidgetSize * 0.65
          }

          // Discoverability toggle (advertising)
          NIconButton {
            enabled: BluetoothService.enabled
            icon: BluetoothService.discoverable ? "broadcast" : "broadcast-off"
            tooltipText: I18n.tr("bluetooth.panel.discoverable")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              BluetoothService.setDiscoverable(!BluetoothService.discoverable);
            }
          }

          NIconButton {
            enabled: BluetoothService.enabled
            icon: BluetoothService.scanningActive ? "stop" : "refresh"
            tooltipText: I18n.tr("tooltips.refresh-devices")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: BluetoothService.toggleDiscovery()
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      // Adapter not available of disabled
      NBox {
        id: disabledBox
        visible: !(BluetoothService.adapter && BluetoothService.adapter.enabled)
        Layout.fillWidth: true
        Layout.preferredHeight: disabledColumn.implicitHeight + Style.marginM * 2

        // Center the content within this rectangle
        ColumnLayout {
          id: disabledColumn
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginL

          Item {
            Layout.fillHeight: true
          }

          NIcon {
            icon: "bluetooth-off"
            pointSize: 48
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: I18n.tr("bluetooth.panel.disabled")
            pointSize: Style.fontSizeL
            color: Color.mOnSurfaceVariant
            Layout.alignment: Qt.AlignHCenter
          }

          NText {
            text: I18n.tr("bluetooth.panel.enable-message")
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

      NScrollView {
        visible: BluetoothService.adapter && BluetoothService.adapter.enabled
        Layout.fillWidth: true
        Layout.fillHeight: true
        horizontalPolicy: ScrollBar.AlwaysOff
        verticalPolicy: ScrollBar.AsNeeded
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
          id: devicesList
          width: parent.width
          spacing: Style.marginM

          // Connected devices
          BluetoothDevicesList {
            label: I18n.tr("bluetooth.panel.connected-devices")
            headerMode: "layout"
            property var items: {
              if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
                return [];
              var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && dev.connected);
              filtered = BluetoothService.dedupeDevices(filtered);
              return BluetoothService.sortDevices(filtered);
            }
            model: items
            visible: items.length > 0
            Layout.fillWidth: true
          }

          // Paired devices
          BluetoothDevicesList {
            label: I18n.tr("bluetooth.panel.paired-devices")
            headerMode: "layout"
            property var items: {
              if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
                return [];
              var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && !dev.connected && (dev.paired || dev.trusted));
              filtered = BluetoothService.dedupeDevices(filtered);
              return BluetoothService.sortDevices(filtered);
            }
            model: items
            visible: items.length > 0
            Layout.fillWidth: true
          }

          // Available devices (for pairing)
          BluetoothDevicesList {
            label: I18n.tr("bluetooth.panel.available-devices")
            headerMode: "filter"
            property var items: {
              if (!BluetoothService.adapter || !BluetoothService.adapter.devices)
                return [];
              var filtered = BluetoothService.adapter.devices.values.filter(dev => dev && !dev.blocked && !dev.paired && !dev.trusted);
              // Optionally hide devices without a meaningful name when the filter is enabled
              if (Settings.data && Settings.data.ui && Settings.data.network.bluetoothHideUnnamedDevices) {
                filtered = filtered.filter(function (dev) {
                  // Extract display name
                  var dn = "";
                  if (dev && dev.name)
                    dn = dev.name;
                  else if (dev && dev.deviceName)
                    dn = dev.deviceName;
                  else
                    dn = "";
                  if (dn === undefined || dn === null)
                    dn = "";
                  var s = String(dn).trim();

                  // 1) Hide empty or whitespace-only
                  if (s.length === 0)
                    return false;

                  // 2) Hide common placeholders
                  var lower = s.toLowerCase();
                  if (lower === "unknown" || lower === "unnamed" || lower === "n/a" || lower === "na")
                    return false;

                  // 3) Hide if the name equals the device address (ignoring separators)
                  var addr = "";
                  if (dev && dev.address)
                    addr = String(dev.address);
                  else if (dev && dev.bdaddr)
                    addr = String(dev.bdaddr);
                  else if (dev && dev.mac)
                    addr = String(dev.mac);
                  if (addr && addr.length > 0) {
                    var normName = s.toLowerCase().replace(/[^0-9a-z]/g, "");
                    var normAddr = addr.toLowerCase().replace(/[^0-9a-z]/g, "");
                    if (normName.length > 0 && normName === normAddr)
                      return false;
                  }

                  // 4) Hide address-like strings
                  //   - Colon-separated hex: 00:11:22:33:44:55
                  var macColonHex = /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/;
                  if (macColonHex.test(s))
                    return false;
                  //   - Hyphen-separated hex: 00-11-22-33-44-55
                  var macHyphenHex = /^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$/;
                  if (macHyphenHex.test(s))
                    return false;
                  //   - Hyphen-separated alnum pairs (to catch non-hex variants like AB-CD-EF-GH-01-23)
                  var macHyphenAny = /^([0-9A-Za-z]{2}-){5}[0-9A-Za-z]{2}$/;
                  if (macHyphenAny.test(s))
                    return false;
                  //   - Cisco dotted hex: 0011.2233.4455
                  var macDotted = /^[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}$/;
                  if (macDotted.test(s))
                    return false;
                  //   - Bare hex: 001122334455
                  var macBare = /^[0-9A-Fa-f]{12}$/;
                  if (macBare.test(s))
                    return false;

                  // Keep device otherwise (has a meaningful user-facing name)
                  return true;
                });
              }
              filtered = BluetoothService.dedupeDevices(filtered);
              return BluetoothService.sortDevices(filtered);
            }
            model: items
            visible: items.length > 0
            Layout.fillWidth: true
          }

          // Empty state when no devices
          NBox {
            visible: {
              if (!(BluetoothService.adapter && BluetoothService.adapter.devices) || BluetoothService.scanningActive)
                return false;

              var availableCount = BluetoothService.adapter.devices.values.filter(dev => {
                                                                                    return dev && !dev.blocked && (dev.signalStrength === undefined || dev.signalStrength > 0);
                                                                                  }).length;
              return (availableCount === 0);
            }
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
                icon: "bluetooth"
                pointSize: 48
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NText {
                text: I18n.tr("bluetooth.panel.no-devices")
                pointSize: Style.fontSizeL
                color: Color.mOnSurfaceVariant
                Layout.alignment: Qt.AlignHCenter
              }

              NButton {
                text: I18n.tr("tooltips.refresh-devices")
                icon: "refresh"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                  BluetoothService.toggleDiscovery();
                }
              }

              Item {
                Layout.fillHeight: true
              }
            }
          }

          // Fallback - No devices, scanning
          NBox {
            Layout.fillWidth: true
            Layout.preferredHeight: scanningColumn.implicitHeight + Style.marginM * 2
            visible: {
              if (!(BluetoothService.adapter && BluetoothService.adapter.devices) || !BluetoothService.scanningActive) {
                return false;
              }

              var availableCount = BluetoothService.adapter.devices.values.filter(dev => {
                                                                                    return dev && !dev.paired && !dev.pairing && !dev.blocked && (dev.signalStrength === undefined || dev.signalStrength > 0);
                                                                                  }).length;
              return (availableCount === 0);
            }

            ColumnLayout {
              id: scanningColumn
              anchors.fill: parent
              anchors.margins: Style.marginM
              spacing: Style.marginL

              Item {
                Layout.fillHeight: true
              }

              RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Style.marginXS

                NIcon {
                  icon: "refresh"
                  pointSize: Style.fontSizeXXL * 1.5
                  color: Color.mPrimary

                  RotationAnimation on rotation {
                    running: true
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: Style.animationSlow * 4
                  }
                }

                NText {
                  text: I18n.tr("bluetooth.panel.scanning")
                  pointSize: Style.fontSizeL
                  color: Color.mOnSurface
                }
              }

              NText {
                text: I18n.tr("bluetooth.panel.pairing-mode")
                pointSize: Style.fontSizeM
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
        }
      }
    }
  }
}
