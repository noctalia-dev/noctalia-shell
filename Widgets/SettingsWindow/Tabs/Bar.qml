import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
                text: "Elements"
                font.pixelSize: 18 * Theme.scale(Screen)
                font.bold: true
                color: Theme.textPrimary
                Layout.bottomMargin: 16 * Theme.scale(Screen)
            }

            ToggleOption {
                label: "Show Active Window"
                description: "Display the title of the currently focused window below the bar"
                value: Settings.settings.showActiveWindow
                onToggled: function() {
                    Settings.settings.showActiveWindow = !Settings.settings.showActiveWindow;
                }
            }

            ToggleOption {
                label: "Show Active Window Icon"
                description: "Display the icon of the currently focused window"
                value: Settings.settings.showActiveWindowIcon
                onToggled: function() {
                    Settings.settings.showActiveWindowIcon = !Settings.settings.showActiveWindowIcon;
                }
            }

            ToggleOption {
                label: "Show System Info"
                description: "Display system information (CPU, RAM, Temperature)"
                value: Settings.settings.showSystemInfoInBar
                onToggled: function() {
                    Settings.settings.showSystemInfoInBar = !Settings.settings.showSystemInfoInBar;
                }
            }

            ToggleOption {
                label: "Show Taskbar"
                description: "Display a taskbar showing currently open windows"
                value: Settings.settings.showTaskbar
                onToggled: function() {
                    Settings.settings.showTaskbar = !Settings.settings.showTaskbar;
                }
            }

            ToggleOption {
                label: "Show Media"
                description: "Display media controls and information"
                value: Settings.settings.showMediaInBar
                onToggled: function() {
                    Settings.settings.showMediaInBar = !Settings.settings.showMediaInBar;
                }
            }

        }

    }

}
