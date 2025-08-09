import QtQuick
import qs.Settings
import qs.Components
import Quickshell.Io

Item {
    id: idleToggle

    // Provided by Bar
    property var shell
    property var screen: (typeof modelData !== 'undefined' ? modelData : null)

    property bool inhibited: true

    width: 22
    height: 22

    // Icon
    Text {
        id: iconText
        anchors.centerIn: parent
        text: idleToggle.inhibited ? "bedtime" : "wb_sunny"
        // Use filled vs outlined to indicate state
        font.family: (mouseArea.containsMouse || idleToggle.inhibited) ? "Material Symbols Rounded" : "Material Symbols Outlined"
        font.pixelSize: 16 * Theme.scale(screen)
        color: idleToggle.inhibited ? Theme.accentPrimary : (mouseArea.containsMouse ? Theme.accentPrimary : Theme.textPrimary)
    }

    Process {
        id: executor
        command: ["qs", "ipc", "call", "globalIPC", "toggleIdleInhibitor"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim();
                if (out === "true" || out === "false") {
                    idleToggle.inhibited = (out === "true");
                } else {
                    console.warn("[IdleToggle] Unexpected output:", out);
                }
            }
        }
        onExited: {
            console.log("[IdleToggle] toggleLauncher finished");
        }
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
            executor.running = true;
        }
    }
}
