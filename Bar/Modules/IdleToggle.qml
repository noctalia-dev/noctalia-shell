import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Components
import qs.Settings
import qs.Helpers


Item {
    id: root

    // Optional explicit inhibitor instance (will override shell lookup if set)
    property var shell

    property IdleInhibitor inhibitor: shell.idleInhibitorRef

    // Visual customization
    property int size: 22
    property string iconActive: "wb_sunny"
    property string iconInactive: "bedtime"
    property string tooltipOn: "Idle inhibitor: On"
    property string tooltipOff: "Idle inhibitor: Off"

    // Derived state and styling
    property bool isActive: root.inhibitor.isRunning
    property color hoverBg: Theme.highlight
    property color activeBg: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.12)

    width: size
    height: size

    // Inline ActionButton implementation
    Rectangle {
        id: button
        anchors.fill: parent
        color: root.isActive ? root.activeBg : "transparent"
        radius: width / 2

        Text {
            anchors.centerIn: parent
            text: root.isActive ? root.iconActive : root.iconInactive
            font.family: mouseArea.containsMouse || root.isActive ? "Material Symbols Rounded" : "Material Symbols Outlined"
            font.pixelSize: 16 * Theme.scale(Screen)
            color: mouseArea.containsMouse || root.isActive ? Theme.accentPrimary : Theme.textPrimary
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.inhibitor && typeof root.inhibitor.toggle === 'function') {
                    root.inhibitor.toggle();
                } else {
                    console.warn("IdleToggle: inhibitor instance not available");
                }
            }
        }

        StyledTooltip {
            text: "Idle Inhibitor"
            targetItem: mouseArea
            tooltipVisible: mouseArea.containsMouse
        }
    }
}
