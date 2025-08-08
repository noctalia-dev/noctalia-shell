import QtQuick 
import Quickshell
import Quickshell.Io
import qs.Settings
import qs.Components

Item {
    id: root
    width: 22; height: 22
    property bool isSilence: false
    property var shell: null

    Process {
        id: rightClickProcess
        command: ["qs","ipc", "call", "globalIPC", "toggleNotificationPopup"]
    }

    // Timer to check when NotificationHistory is loaded
    Timer {
        id: checkHistoryTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (shell && shell.notificationHistoryWin) {
                shell.notificationHistoryWin.visible = true;
                checkHistoryTimer.stop();
            }
        }
    }

    Item {
        id: bell
        width: 22; height: 22
        Text {
            id: bellText
            anchors.centerIn: parent
            text: {
                if (shell && shell.notificationHistoryWin && shell.notificationHistoryWin.hasUnread) {
                    return "notifications_unread";
                } else {
                    return "notifications";
                }
            }
            font.family: mouseAreaBell.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
            font.pixelSize: 16 * Theme.scale(Screen)
            font.weight: {
                if (shell && shell.notificationHistoryWin && shell.notificationHistoryWin.hasUnread) {
                    return Font.Bold;
                } else {
                    return Font.Normal;
                }
            }
            color: mouseAreaBell.containsMouse ? Theme.accentPrimary : (shell && shell.notificationHistoryWin && shell.notificationHistoryWin.hasUnread ? Theme.accentPrimary : Theme.textDisabled)
        }
        MouseArea {
            id: mouseAreaBell
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    root.isSilence = !root.isSilence;
                    rightClickProcess.running = true;
                    bellText.text = root.isSilence ? "notifications_off" : "notifications"
                }

                if (mouse.button === Qt.LeftButton){
                    if (shell) {
                        if (!shell.notificationHistoryWin) {
                            // Use the shell function to load notification history
                            shell.loadNotificationHistory();
                            checkHistoryTimer.start();
                        } else {
                            // Already loaded, just toggle visibility
                            shell.notificationHistoryWin.visible = !shell.notificationHistoryWin.visible;
                        }
                    }
                    return;
                }
            }
            onEntered: notificationTooltip.tooltipVisible = true
            onExited: notificationTooltip.tooltipVisible = false
        }
    }

    StyledTooltip {
        id: notificationTooltip
        text: "Notification History"
        positionAbove: false
        tooltipVisible: false
        targetItem: bell
        delay: 200
    }
}
