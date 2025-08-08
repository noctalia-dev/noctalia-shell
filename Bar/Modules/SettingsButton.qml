import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Settings
import qs.Components
import qs.Widgets.SettingsWindow

Item {
    id: root
    width: 22
    height: 22

    Rectangle {
        id: button
        anchors.fill: parent
        color: "transparent"
        radius: width / 2

        Text {
            anchors.centerIn: parent
            text: "settings"
            font.family: "Material Symbols Outlined"
            font.pixelSize: 16 * Theme.scale(Screen)
            color: mouseArea.containsMouse ? Theme.accentPrimary : Theme.textPrimary
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor

            onClicked: {
                if (!settingsWindowLoader.active) {
                    // Start loading the settings window
                    settingsWindowLoader.loading = true;
                }
                
                if (settingsWindowLoader.item) {
                    // Toggle visibility
                    if (settingsWindowLoader.item.visible) {
                        settingsWindowLoader.item.visible = false;
                    } else {
                        settingsWindowLoader.item.visible = true;
                    }
                }
            }
        }

        StyledTooltip {
            text: "Settings"
            targetItem: mouseArea
            tooltipVisible: mouseArea.containsMouse
        }
    }

    // LazyLoader for SettingsWindow
    LazyLoader {
        id: settingsWindowLoader
        loading: false
        component: SettingsWindow {
            // Handle window closure - just hide it, don't destroy
            onVisibleChanged: {
                if (!visible) {
                    // Window is hidden, but keep it loaded for reuse
                }
            }
        }
    }
}