import QtQuick
import qs.Settings
import qs.Components
import qs.Helpers

Item {
    id: idleToggle

    // Provided by Bar
    property var shell
    property var screen: (typeof modelData !== 'undefined' ? modelData : null)
    property IdleInhibitor inhibitor: idleToggle.shell.mainLoaderRef.item.idleInhibitorRef
    property bool inhibited: inhibitor.isRunning

    width: 22
    height: 22

    // Icon
    Text {
        id: iconText
        anchors.centerIn: parent
        text: idleToggle.inhibited ? "wb_sunny" : "bedtime"
        // Use filled vs outlined to indicate state
        font.family: (mouseArea.containsMouse || idleToggle.inhibited) ? "Material Symbols Rounded" : "Material Symbols Outlined"
        font.pixelSize: 16 * Theme.scale(screen)
        color: idleToggle.inhibited ? Theme.accentPrimary : (mouseArea.containsMouse ? Theme.accentPrimary : Theme.textPrimary)
    }

    // Tooltip
    StyledTooltip {
        id: tooltip
        text: idleToggle.inhibited ? "Idle inhibitor: ON (click to disable)" : "Idle inhibitor: OFF (click to enable)"
        positionAbove: false
        tooltipVisible: mouseArea.containsMouse
        targetItem: idleToggle
        delay: 250
    }

    // Interaction
    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            idleToggle.inhibitor.toggle()
        }
    }
}
