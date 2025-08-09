import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings

ColumnLayout {
    id: root

    property var screen

    property string label: ""
    property string description: ""
    property bool value: false
    property var onToggled: function() {
    }

    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true

        ColumnLayout {
            spacing: 4 * Theme.scale(screen)
            Layout.fillWidth: true

            Text {
                text: label
                font.pixelSize: 13 * Theme.scale(screen)
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                text: description
                font.pixelSize: 12 * Theme.scale(screen)
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

        }

        Rectangle {
            id: switcher

            width: 52 * Theme.scale(screen)
            height: 32 * Theme.scale(screen)
            radius: 16
            color: value ? Theme.accentPrimary : Theme.surfaceVariant
            border.color: value ? Theme.accentPrimary : Theme.outline
            border.width: 2 * Theme.scale(screen)

            Rectangle {
                width: 28 * Theme.scale(screen)
                height: 28 * Theme.scale(screen)
                radius: 14
                color: Theme.surface
                border.color: Theme.outline
                border.width: 1 * Theme.scale(screen)
                y: 2
                x: value ? switcher.width - width - 2 : 2

                Behavior on x {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }

                }

            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.onToggled();
                }
            }

        }

    }

    Rectangle {
        height: 8 * Theme.scale(screen)
    }

}
