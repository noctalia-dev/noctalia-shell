import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Bluetooth
import qs.Settings
import qs.Components

Item {
    id: root
    width: Settings.settings.bluetoothEnabled ? 22 : 0
    height: Settings.settings.bluetoothEnabled ? 22 : 0

    property bool menuVisible: false

    // Bluetooth icon/button
    Item {
        id: bluetoothIcon
        width: 22; height: 22
        visible: Settings.settings.bluetoothEnabled

            // Check if any devices are currently connected
    property bool hasConnectedDevices: {
        if (!Bluetooth.defaultAdapter) return false;
        
        for (let i = 0; i < Bluetooth.defaultAdapter.devices.count; i++) {
            if (Bluetooth.defaultAdapter.devices.valueAt(i).connected) {
                return true;
            }
        }
        return false;
    }

        Text {
            id: bluetoothText
            anchors.centerIn: parent
            text: {
                if (!Bluetooth.defaultAdapter || !Bluetooth.defaultAdapter.enabled) {
                    return "bluetooth_disabled"
                } else if (parent.hasConnectedDevices) {
                    return "bluetooth_connected"
                } else {
                    return "bluetooth"
                }
            }
            font.family: mouseAreaBluetooth.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
            font.pixelSize: 16 * Theme.scale(Screen)
            color: mouseAreaBluetooth.containsMouse ? Theme.accentPrimary : Theme.textPrimary
        }

        MouseArea {
            id: mouseAreaBluetooth
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!bluetoothMenuLoader.active) {
                    bluetoothMenuLoader.loading = true;
                }
                if (bluetoothMenuLoader.item) {
                    bluetoothMenuLoader.item.visible = !bluetoothMenuLoader.item.visible;
                    // Enable adapter and start discovery when menu opens
                    if (bluetoothMenuLoader.item.visible && Bluetooth.defaultAdapter) {
                        if (!Bluetooth.defaultAdapter.enabled) {
                            Bluetooth.defaultAdapter.enabled = true;
                        }
                        if (!Bluetooth.defaultAdapter.discovering) {
                            Bluetooth.defaultAdapter.discovering = true;
                        }
                    }
                }
            }
            onEntered: bluetoothTooltip.tooltipVisible = true
            onExited: bluetoothTooltip.tooltipVisible = false
        }
    }

    StyledTooltip {
        id: bluetoothTooltip
        text: "Bluetooth Devices"
        positionAbove: false
        tooltipVisible: false
        targetItem: bluetoothIcon
        delay: 200
    }

    // LazyLoader for Bluetooth menu
    LazyLoader {
        id: bluetoothMenuLoader
        loading: false
        component: PanelWindow {
            id: bluetoothMenu
            implicitWidth: 320
            implicitHeight: 480
            visible: false
            color: "transparent"
            anchors.top: true
            anchors.right: true
            margins.right: 0
            margins.top: 0
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

            onVisibleChanged: {
                // Stop discovery when menu closes to save battery
                if (!visible && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) {
                    Bluetooth.defaultAdapter.discovering = false;
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.backgroundPrimary
                radius: 12

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "bluetooth"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24 * Theme.scale(Screen)
                            color: Theme.accentPrimary
                        }

                        Text {
                            text: "Bluetooth Devices"
                            font.pixelSize: 18 * Theme.scale(Screen)
                            font.bold: true
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: "close"
                            onClicked: {
                                bluetoothMenu.visible = false;
                                if (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) {
                                    Bluetooth.defaultAdapter.discovering = false;
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Theme.outline
                        opacity: 0.12
                    }

                    ListView {
                        id: deviceList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices : []
                        spacing: 8
                        clip: true

                        delegate: Item {
                            width: parent.width
                            height: 48

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: modelData.connected ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.44) : (deviceMouseArea.containsMouse ? Theme.highlight : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    Text {
                                        text: modelData.connected ? "bluetooth" : "bluetooth_disabled"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 18 * Theme.scale(Screen)
                                        color: deviceMouseArea.containsMouse ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textSecondary)
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: {
                                                let deviceName = modelData.name || modelData.deviceName || "Unknown Device";
                                                // Hide MAC addresses and show "Unknown Device" instead
                                                let macPattern = /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/;
                                                if (macPattern.test(deviceName)) {
                                                    return "Unknown Device";
                                                }
                                                return deviceName;
                                            }
                                            color: deviceMouseArea.containsMouse ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textPrimary)
                                            font.pixelSize: 14 * Theme.scale(Screen)
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: {
                                                let deviceName = modelData.name || modelData.deviceName || "";
                                                let macPattern = /^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/;
                                                if (macPattern.test(deviceName)) {
                                                    // Show MAC address in subtitle for unnamed devices
                                                    return modelData.address + " • " + (modelData.paired ? "Paired" : "Available");
                                                } else {
                                                    // Show only status for named devices
                                                    return modelData.paired ? "Paired" : "Available";
                                                }
                                            }
                                            color: deviceMouseArea.containsMouse ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textSecondary)
                                            font.pixelSize: 11 * Theme.scale(Screen)
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }

                                    Item {
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        visible: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting

                                        Spinner {
                                            visible: parent.visible
                                            running: parent.visible
                                            color: Theme.accentPrimary
                                            anchors.centerIn: parent
                                            size: 22
                                        }
                                    }
                                }

                                MouseArea {
                                    id: deviceMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        // Handle device actions: disconnect, pair, or connect
                                        if (modelData.connected) {
                                            modelData.disconnect();
                                        } else if (!modelData.paired) {
                                            modelData.pair();
                                        } else {
                                            modelData.connect();
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Discovering indicator
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering

                        Text {
                            text: "Scanning for devices..."
                            font.pixelSize: 12 * Theme.scale(Screen)
                            color: Theme.textSecondary
                        }

                        Spinner {
                            running: true
                            color: Theme.accentPrimary
                            size: 16
                        }
                    }
                }
            }
        }
    }
}