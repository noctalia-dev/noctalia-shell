import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Components
import qs.Settings
import qs.Widgets.SettingsWindow

// Record and Wallpaper card
Rectangle {
    color: Theme.surface
    radius: 18 * Theme.scale(screen)

    property var screen: (typeof modelData !== 'undefined' ? modelData : null)

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 20 * Theme.scale(screen)

        // Record button
        Rectangle {
            id: recordButton

            width: 36 * Theme.scale(screen)
            height: 36 * Theme.scale(screen)
            radius: width * 0.5
            border.color: Theme.accentPrimary
            border.width: 1 * Theme.scale(screen)
            color: sidebarPopupRect.isRecording ? Theme.accentPrimary : (recordButtonArea.containsMouse ? Theme.accentPrimary : "transparent")

            Text {
                anchors.centerIn: parent
                text: "photo_camera"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 22 * Theme.scale(screen)
                color: sidebarPopupRect.isRecording || recordButtonArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
                id: recordButtonArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (sidebarPopupRect.isRecording) {
                        sidebarPopupRect.stopRecording();
                        sidebarPopup.dismiss();
                    } else {
                        sidebarPopupRect.startRecording();
                        sidebarPopup.dismiss();
                    }
                }
            }

            StyledTooltip {
                text: sidebarPopupRect.isRecording ? "Stop Recording" : "Start Recording"
                targetItem: recordButtonArea
                tooltipVisible: recordButtonArea.containsMouse
            }

        }

        // Wallpaper button
        Rectangle {
            id: wallpaperButton

            width: 36 * Theme.scale(screen)
            height: 36 * Theme.scale(screen)
            radius: width * 0.5
            border.color: Theme.accentPrimary
            border.width: 1 * Theme.scale(screen)
            color: wallpaperButtonArea.containsMouse ? Theme.accentPrimary : "transparent"

            Text {
                anchors.centerIn: parent
                text: "image"
                font.family: "Material Symbols Outlined"
                font.pixelSize: 22 * Theme.scale(screen)
                color: wallpaperButtonArea.containsMouse ? Theme.backgroundPrimary : Theme.accentPrimary
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }

            MouseArea {
                id: wallpaperButtonArea

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (typeof settingsModal !== 'undefined' && settingsModal && settingsModal.openSettings) {
                        settingsModal.openSettings(6);
                        sidebarPopup.dismiss();
                    }
                }
            }

            StyledTooltip {
                text: "Wallpaper"
                targetItem: wallpaperButtonArea
                tooltipVisible: wallpaperButtonArea.containsMouse
            }

        }

    }

}
