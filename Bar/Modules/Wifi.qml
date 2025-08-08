import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Settings
import qs.Components
import qs.Services

Item {
    id: root
    width: Settings.settings.wifiEnabled ? 22 : 0
    height: Settings.settings.wifiEnabled ? 22 : 0

    property bool menuVisible: false
    property string passwordPromptSsid: ""
    property string passwordInput: ""
    property bool showPasswordPrompt: false

    Network {
        id: network
    }

    // WiFi icon/button
    Item {
        id: wifiIcon
        width: 22; height: 22
        visible: Settings.settings.wifiEnabled

        property int currentSignal: {
            let maxSignal = 0;
            for (const net in network.networks) {
                if (network.networks[net].connected && network.networks[net].signal > maxSignal) {
                    maxSignal = network.networks[net].signal;
                }
            }
            return maxSignal;
        }

        Text {
            id: wifiText
            anchors.centerIn: parent
            text: {
                let connected = false;
                for (const net in network.networks) {
                    if (network.networks[net].connected) {
                        connected = true;
                        break;
                    }
                }
                return connected ? network.signalIcon(parent.currentSignal) : "wifi_off"
            }
            font.family: mouseAreaWifi.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
            font.pixelSize: 16 * Theme.scale(Screen)
            color: mouseAreaWifi.containsMouse ? Theme.accentPrimary : Theme.textPrimary
        }

        MouseArea {
            id: mouseAreaWifi
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!wifiMenuLoader.active) {
                    wifiMenuLoader.loading = true;
                }
                if (wifiMenuLoader.item) {
                    wifiMenuLoader.item.visible = !wifiMenuLoader.item.visible;
                    if (wifiMenuLoader.item.visible) {
                        network.onMenuOpened();
                    } else {
                        network.onMenuClosed();
                    }
                }
            }
            onEntered: wifiTooltip.tooltipVisible = true
            onExited: wifiTooltip.tooltipVisible = false
        }
    }

    StyledTooltip {
        id: wifiTooltip
        text: "WiFi Networks"
        positionAbove: false
        tooltipVisible: false
        targetItem: wifiIcon
        delay: 200
    }

    // LazyLoader for WiFi menu
    LazyLoader {
        id: wifiMenuLoader
        loading: false
        component: PanelWindow {
            id: wifiMenu
            implicitWidth: 320
            implicitHeight: 480
            visible: false
            color: "transparent"
            anchors.top: true
            anchors.right: true
            margins.right: 0
            margins.top: 0
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

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
                            text: "wifi"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: 24 * Theme.scale(Screen)
                            color: Theme.accentPrimary
                        }

                        Text {
                            text: "WiFi Networks"
                            font.pixelSize: 18 * Theme.scale(Screen)
                            font.bold: true
                            color: Theme.textPrimary
                            Layout.fillWidth: true
                        }

                        IconButton {
                            icon: "refresh"
                            onClicked: network.refreshNetworks()
                        }

                        IconButton {
                            icon: "close"
                            onClicked: {
                                wifiMenu.visible = false;
                                network.onMenuClosed();
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
                        id: networkList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: Object.values(network.networks)
                        spacing: 8
                        clip: true

                        delegate: Item {
                            width: parent.width
                            height: modelData.ssid === passwordPromptSsid && showPasswordPrompt ? 108 : 48 // 48 for network + 60 for password prompt

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: 8
                                    color: modelData.connected ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.44) : (networkMouseArea.containsMouse ? Theme.highlight : "transparent")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8

                                        Text {
                                            text: network.signalIcon(modelData.signal)
                                            font.family: "Material Symbols Outlined"
                                            font.pixelSize: 18 * Theme.scale(Screen)
                                            color: networkMouseArea.containsMouse ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textSecondary)
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            Text {
                                                text: modelData.ssid || "Unknown Network"
                                                color: networkMouseArea.containsMouse ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textPrimary)
                                                font.pixelSize: 14 * Theme.scale(Screen)
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: modelData.security && modelData.security !== "--" ? modelData.security : "Open"
                                                color: networkMouseArea.containsMouse ? Theme.backgroundPrimary : (modelData.connected ? Theme.accentPrimary : Theme.textSecondary)
                                                font.pixelSize: 11 * Theme.scale(Screen)
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                visible: network.connectStatusSsid === modelData.ssid && network.connectStatus === "error" && network.connectError.length > 0
                                                text: network.connectError
                                                color: Theme.error
                                                font.pixelSize: 11 * Theme.scale(Screen)
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }

                                        Item {
                                            Layout.preferredWidth: 22
                                            Layout.preferredHeight: 22
                                            visible: network.connectStatusSsid === modelData.ssid && (network.connectStatus !== "" || network.connectingSsid === modelData.ssid)

                                            Spinner {
                                                visible: network.connectingSsid === modelData.ssid
                                                running: network.connectingSsid === modelData.ssid
                                                color: Theme.accentPrimary
                                                anchors.centerIn: parent
                                                size: 22
                                            }

                                            Text {
                                                visible: network.connectStatus === "success" && !network.connectingSsid
                                                text: "check_circle"
                                                font.family: "Material Symbols Outlined"
                                                font.pixelSize: 18 * Theme.scale(Screen)
                                                color: "#43a047"
                                                anchors.centerIn: parent
                                            }

                                            Text {
                                                visible: network.connectStatus === "error" && !network.connectingSsid
                                                text: "error"
                                                font.family: "Material Symbols Outlined"
                                                font.pixelSize: 18 * Theme.scale(Screen)
                                                color: Theme.error
                                                anchors.centerIn: parent
                                            }
                                        }

                                        Text {
                                            visible: modelData.connected
                                            text: "connected"
                                            color: networkMouseArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
                                            font.pixelSize: 11 * Theme.scale(Screen)
                                        }
                                    }

                                    MouseArea {
                                        id: networkMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (modelData.connected) {
                                                network.disconnectNetwork(modelData.ssid);
                                            } else if (network.isSecured(modelData.security) && !modelData.existing) {
                                                passwordPromptSsid = modelData.ssid;
                                                showPasswordPrompt = true;
                                                passwordInput = ""; // Clear previous input
                                                Qt.callLater(function() {
                                                    passwordInputField.forceActiveFocus();
                                                });
                                            } else {
                                                network.connectNetwork(modelData.ssid, modelData.security);
                                            }
                                        }
                                    }
                                }

                                // Password prompt section
                                Rectangle {
                                    id: passwordPromptSection
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: modelData.ssid === passwordPromptSsid && showPasswordPrompt ? 60 : 0
                                    Layout.margins: 8
                                    visible: modelData.ssid === passwordPromptSsid && showPasswordPrompt
                                    color: Theme.surfaceVariant
                                    radius: 8

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 12
                                        spacing: 10

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 8
                                                color: "transparent"
                                                border.color: passwordInputField.activeFocus ? Theme.accentPrimary : Theme.outline
                                                border.width: 1

                                                TextInput {
                                                    id: passwordInputField
                                                    anchors.fill: parent
                                                    anchors.margins: 12
                                                    text: passwordInput
                                                    font.pixelSize: 13 * Theme.scale(Screen)
                                                    color: Theme.textPrimary
                                                    verticalAlignment: TextInput.AlignVCenter
                                                    clip: true
                                                    focus: true
                                                    selectByMouse: true
                                                    activeFocusOnTab: true
                                                    inputMethodHints: Qt.ImhNone
                                                    echoMode: TextInput.Password
                                                    onTextChanged: passwordInput = text
                                                    onAccepted: {
                                                        network.submitPassword(passwordPromptSsid, passwordInput);
                                                        showPasswordPrompt = false;
                                                    }

                                                    MouseArea {
                                                        id: passwordInputMouseArea
                                                        anchors.fill: parent
                                                        onClicked: passwordInputField.forceActiveFocus()
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 80
                                            Layout.preferredHeight: 36
                                            radius: 18
                                            color: Theme.accentPrimary
                                            border.color: Theme.accentPrimary
                                            border.width: 0
                                            opacity: 1.0

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 100
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: {
                                                    network.submitPassword(passwordPromptSsid, passwordInput);
                                                    showPasswordPrompt = false;
                                                }
                                                cursorShape: Qt.PointingHandCursor
                                                hoverEnabled: true
                                                onEntered: parent.color = Qt.darker(Theme.accentPrimary, 1.1)
                                                onExited: parent.color = Theme.accentPrimary
                                            }

                                            Text {
                                                anchors.centerIn: parent
                                                text: "Connect"
                                                color: Theme.backgroundPrimary
                                                font.pixelSize: 14 * Theme.scale(Screen)
                                                font.bold: true
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