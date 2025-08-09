import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs.Components
import qs.Settings

ColumnLayout {
    id: root

    spacing: 0
    anchors.fill: parent
    anchors.margins: 0

    ScrollView {
        id: scrollView

        Layout.fillWidth: true
        Layout.fillHeight: true
        padding: 16
        rightPadding: 12
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            width: scrollView.availableWidth
            spacing: 0

            Text {
                text: "Wi-Fi"
                font.pixelSize: 18 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            ToggleOption {
                label: "Enable Wi-Fi"
                description: "Turn Wi-Fi radio on or off"
                value: Settings.settings.wifiEnabled
                onToggled: function() {
                    Settings.settings.wifiEnabled = !Settings.settings.wifiEnabled;
                    Quickshell.execDetached(["nmcli", "radio", "wifi", Settings.settings.wifiEnabled ? "on" : "off"]);
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 26
                Layout.bottomMargin: 18
                height: 1
                color: Theme.outline
                opacity: 0.3
            }

            Text {
                text: "Bluetooth"
                font.pixelSize: 18 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(screen)
            }

            ToggleOption {
                label: "Enable Bluetooth"
                description: "Turn Bluetooth radio on or off"
                value: Settings.settings.bluetoothEnabled
                onToggled: function() {
                                            Settings.settings.bluetoothEnabled = !Settings.settings.bluetoothEnabled;
                    if (Bluetooth.defaultAdapter) {

                        Bluetooth.defaultAdapter.enabled = Settings.settings.bluetoothEnabled;
                        if (Bluetooth.defaultAdapter.enabled)
                            Bluetooth.defaultAdapter.discovering = true;

                    }
                }
            }

        }

    }

}
