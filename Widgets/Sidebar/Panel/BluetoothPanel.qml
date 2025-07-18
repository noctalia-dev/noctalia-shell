import QtQuick 
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Wayland
import Quickshell
import Quickshell.Bluetooth
import qs.Settings
import qs.Components
import qs.Helpers

Item {
    id: root
    property alias panel: bluetoothPanelModal

    // For showing error/status messages
    property string statusMessage: ""
    property bool statusPopupVisible: false

    function showStatus(msg) {
        statusMessage = msg
        statusPopupVisible = true
    }

    function hideStatus() {
        statusPopupVisible = false
    }

    function showAt() {
        bluetoothLogic.showAt()
    }

    Rectangle {
        id: card
        width: 36; height: 36
        radius: 18
        border.color: Theme.accentPrimary
        border.width: 1
        color: bluetoothButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

        Text {
            anchors.centerIn: parent
            text: "bluetooth"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 22
            color: bluetoothButtonArea.containsMouse
                ? Theme.backgroundPrimary
                : Theme.accentPrimary
        }

        MouseArea {
            id: bluetoothButtonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: bluetoothLogic.showAt()
        }
    }

    QtObject {
        id: bluetoothLogic

        function showAt() {
            if (Bluetooth.defaultAdapter) {
                if (!Bluetooth.defaultAdapter.enabled)
                    Bluetooth.defaultAdapter.enabled = true
                if (!Bluetooth.defaultAdapter.discovering)
                    Bluetooth.defaultAdapter.discovering = true
            }
            bluetoothPanelModal.visible = true
        }
    }

    PanelWindow {
        id: bluetoothPanelModal
        implicitWidth: 480
        implicitHeight: 800
        visible: false
        color: "transparent"
        anchors.top: true
        anchors.right: true
        margins.right: 0
        margins.top: 0
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        onVisibleChanged: {
            if (!visible && Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering)
                Bluetooth.defaultAdapter.discovering = false
        }

        Rectangle {
            anchors.fill: parent
            color: Theme.backgroundPrimary
            radius: 24

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 32
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 20
                    Layout.preferredHeight: 48
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Text {
                        text: "bluetooth"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 32
                        color: Theme.accentPrimary
                    }
                    Text {
                        text: "Bluetooth"
                        font.family: Theme.fontFamily
                        font.pixelSize: 26
                        font.bold: true
                        color: Theme.textPrimary
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        width: 36; height: 36; radius: 18
                        color: closeButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                        border.color: Theme.accentPrimary
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "close"
                            font.family: closeButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                            font.pixelSize: 20
                            color: closeButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                        }
                        MouseArea {
                            id: closeButtonArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: bluetoothPanelModal.visible = false
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.outline
                    opacity: 0.12
                }

                // Content area (centered, in a card)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 640
                    Layout.alignment: Qt.AlignHCenter
                    Layout.margins: 0
                    color: Theme.surfaceVariant
                    radius: 18
                    border.color: Theme.outline
                    border.width: 1
                    anchors.topMargin: 32

                    Rectangle {
                        id: bg
                        anchors.fill: parent
                        color: Theme.backgroundPrimary
                        radius: 12
                        border.width: 1
                        border.color: Theme.surfaceVariant
                        z: 0
                    }
                    Rectangle {
                        id: header
                        color: "transparent"
                    }
                    Rectangle {
                        id: listContainer
                        anchors.top: header.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 24
                        color: "transparent"
                        clip: true

                        ListView {
                            id: deviceListView
                            anchors.fill: parent
                            spacing: 4
                            boundsBehavior: Flickable.StopAtBounds
                            model: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.devices : []

                            delegate: Rectangle {
                                width: parent.width
                                height: 60
                                color: "transparent"
                                radius: 8

                                property bool userInitiatedDisconnect: false

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: modelData.connected ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.18)
                                        : (deviceMouseArea.containsMouse ? Theme.highlight : "transparent")
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    // Fixed-width icon for alignment
                                    Text {
                                        width: 28
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: modelData.connected ? "bluetooth" : "bluetooth_disabled"
                                        font.family: "Material Symbols Outlined"
                                        font.pixelSize: 20
                                        color: modelData.connected ? Theme.accentPrimary : Theme.textSecondary
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        // Device name always fills width for alignment
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name || "Unknown Device"
                                            font.family: Theme.fontFamily
                                            color: modelData.connected ? Theme.accentPrimary : Theme.textPrimary
                                            font.pixelSize: 14
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.address
                                            font.family: Theme.fontFamily
                                            color: modelData.connected ? Theme.accentPrimary : Theme.textSecondary
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: "Paired: " + modelData.paired + " | Trusted: " + modelData.trusted
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: Theme.textSecondary
                                            visible: true
                                        }
                                        // No "Connected" text here!
                                    }
                                    
                                    Spinner {
                                        running: modelData.pairing || modelData.state === BluetoothDeviceState.Connecting || modelData.state === BluetoothDeviceState.Disconnecting
                                        color: Theme.textPrimary
                                        size: 16
                                        visible: running
                                    }
                                }

                                MouseArea {
                                    id: deviceMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        if (modelData.connected) {
                                            userInitiatedDisconnect = true
                                            modelData.disconnect()
                                        } else if (!modelData.paired) {
                                            modelData.pair()
                                            root.showStatus("Pairing... Please check your phone or system for a PIN dialog.")
                                        } else {
                                            modelData.connect()
                                        }
                                    }
                                }

                                Connections {
                                    target: modelData

                                    function onPairedChanged() {
                                        if (modelData.paired) {
                                            root.showStatus("Paired! Now connecting...")
                                            modelData.connect()
                                        }
                                    }
                                    function onPairingChanged() {
                                        if (!modelData.pairing && !modelData.paired) {
                                            root.showStatus("Pairing failed or was cancelled.")
                                        }
                                    }
                                    function onConnectedChanged() {
                                        userInitiatedDisconnect = false
                                    }
                                    function onStateChanged() {
                                        // Optionally handle more granular feedback here
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 2
                        anchors.top: listContainer.top
                        anchors.bottom: listContainer.bottom
                        width: 4
                        radius: 2
                        color: Theme.textSecondary
                        opacity: deviceListView.contentHeight > deviceListView.height ? 0.3 : 0
                        visible: opacity > 0
                    }
                }
            }
        }

        // Status/Info popup
        Popup {
            id: statusPopup
            x: (parent.width - width) / 2
            y: 40
            width: Math.min(360, parent.width - 40)
            visible: root.statusPopupVisible
            modal: false
            focus: false
            background: Rectangle {
                color: Theme.accentPrimary // Use your theme's accent color
                radius: 8
            }
            contentItem: Text {
                text: root.statusMessage
                color: "white"
                wrapMode: Text.WordWrap
                padding: 12
                font.pixelSize: 14
            }
            onVisibleChanged: {
                if (visible) {
                    // Auto-hide after 3 seconds
                    statusPopupTimer.restart()
                }
            }
        }
    }
}
