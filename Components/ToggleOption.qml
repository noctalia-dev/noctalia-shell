import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings

ColumnLayout {
    id: root

    // Local scale convenience with safe fallback
    readonly property real s: (typeof screen !== 'undefined' && screen) ? Theme.scale(screen) : 1.0

    property string label: ""
    property string description: ""
    property bool value: false
    property var onToggled: function() {
    }

    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true

        ColumnLayout {
            spacing: 4 * s
            Layout.fillWidth: true

            Text {
                text: label
                font.pixelSize: 13 * s
                font.bold: true
                color: Theme.textPrimary
            }

            Text {
                text: description
                font.pixelSize: 12 * s
                color: Theme.textSecondary
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

        }

        Rectangle {
            id: switcher

            width: 52 * s
            height: 32 * s
            radius: height / 2
            color: value ? Theme.accentPrimary : Theme.surfaceVariant
            border.color: value ? Theme.accentPrimary : Theme.outline
            border.width: 2 * s

            Rectangle {
                width: 28 * s
                height: 28 * s
                radius: height / 2
                color: Theme.surface
                border.color: Theme.outline
                border.width: 1 * s
                y: 2 * s
                x: value ? switcher.width - width - 2 * s : 2 * s

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
        height: 8 * s
    }

}
