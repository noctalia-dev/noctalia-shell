import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings


Rectangle {
    id: root
    width: 64 * Theme.scale(Screen)
    height: 32 * Theme.scale(Screen)
    radius: 16 * Theme.scale(Screen)
    color: Theme.surfaceVariant
    border.color: Theme.outline
    border.width: 1 * Theme.scale(Screen)

    property bool useFahrenheit: Settings.settings.useFahrenheit
    
    Rectangle {
        id: slider
        width: parent.width / 2 - 4 * Theme.scale(Screen)
        height: parent.height - 4 * Theme.scale(Screen)
        radius: 14 * Theme.scale(Screen)
        color: Theme.accentPrimary
        x: 2 + (useFahrenheit ? parent.width / 2 : 0)
        y: 2

        Behavior on x {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }

    
    Row {
        anchors.fill: parent
        spacing: 0

        
        Item {
            width: parent.width / 2
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: "°C"
                font.pixelSize: 13 * Theme.scale(Screen)
                font.bold: !useFahrenheit
                color: !useFahrenheit ? Theme.onAccent : Theme.textPrimary
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (useFahrenheit) {
                        Settings.settings.useFahrenheit = false;
                    }
                }
            }
        }

        
        Item {
            width: parent.width / 2
            height: parent.height

            Text {
                anchors.centerIn: parent
                text: "°F"
                font.pixelSize: 13 * Theme.scale(Screen)
                font.bold: useFahrenheit
                color: useFahrenheit ? Theme.onAccent : Theme.textPrimary
                
                Behavior on color {
                    ColorAnimation { duration: 200 }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!useFahrenheit) {
                        Settings.settings.useFahrenheit = true;
                    }
                }
            }
        }
    }
}