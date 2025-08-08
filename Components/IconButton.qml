import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Settings

MouseArea {
    id: root
    property string icon
    property bool enabled: true
    property bool hovering: false
    property real size: 32
    cursorShape: Qt.PointingHandCursor
    implicitWidth: size
    implicitHeight: size

    hoverEnabled: true
    onEntered: hovering = true
    onExited: hovering = false

    Rectangle {
        anchors.fill: parent
        radius: 8 * Theme.scale(Screen)
        color: root.hovering ? Theme.accentPrimary : "transparent"
    }
    Text {
        id: iconText
        anchors.centerIn: parent
        text: root.icon
        font.family: "Material Symbols Outlined"
        font.pixelSize: 24 * Theme.scale(Screen)
        color: root.hovering ? Theme.onAccent : Theme.textPrimary
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        opacity: root.enabled ? 1.0 : 0.5
    }
}