import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Settings
import qs.Components

Item {
    id: taskbar
    width: runningAppsRow.width
    height: Settings.settings.taskbarIconSize
    visible: Settings.settings.showTaskbar

    // Attach custom tooltip
    StyledTooltip {
        id: styledTooltip
        positionAbove: false
    }

    function getAppIcon(toplevel: Toplevel): string {
        if (!toplevel)
            return "";

        let icon = Quickshell.iconPath(toplevel.appId?.toLowerCase(), true);
        if (!icon) {
            icon = Quickshell.iconPath(toplevel.appId, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(toplevel.title?.toLowerCase(), true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(toplevel.title, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath("application-x-executable", true);
        }

        return icon || "";
    }

    Row {
        id: runningAppsRow
        spacing: 8
        height: parent.height

        Repeater {
            model: ToplevelManager ? ToplevelManager.toplevels : null

            delegate: Rectangle {
                id: appButton
                width: Settings.settings.taskbarIconSize
                height: Settings.settings.taskbarIconSize
                radius: Math.max(4, Settings.settings.taskbarIconSize * 0.25)
                color: isActive ? Theme.accentPrimary : (hovered ? Theme.surfaceVariant : "transparent")
                border.color: isActive ? Qt.darker(Theme.accentPrimary, 1.2) : "transparent"
                border.width: 1

                property bool isActive: ToplevelManager.activeToplevel && ToplevelManager.activeToplevel === modelData
                property bool hovered: mouseArea.containsMouse
                property string appId: modelData ? modelData.appId : ""
                property string appTitle: modelData ? modelData.title : ""

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }

                IconImage {
                    id: appIcon
                    width: Math.max(12, Settings.settings.taskbarIconSize * 0.625)
                    height: Math.max(12, Settings.settings.taskbarIconSize * 0.625)
                    anchors.centerIn: parent
                    source: getAppIcon(modelData)
                    visible: source.toString() !== ""
                }

                Text {
                    anchors.centerIn: parent
                    visible: !appIcon.visible
                    text: appButton.appId ? appButton.appId.charAt(0).toUpperCase() : "?"
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(10, Settings.settings.taskbarIconSize * 0.4375 * Theme.scale(Screen))
                    font.bold: true
                    color: appButton.isActive ? Theme.onAccent : Theme.textPrimary
                }

                MouseArea {
                    id: mouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: {
                        var text = appTitle || appId;
                        styledTooltip.text = text.length > 60 ? text.substring(0, 60) + "..." : text;
                        styledTooltip.targetItem = appButton;
                        styledTooltip.tooltipVisible = true;
                    }

                    onExited: {
                        styledTooltip.tooltipVisible = false;
                    }

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.MiddleButton) {
                            if (modelData && modelData.close) {
                                modelData.close();
                            }
                        }

                        if (mouse.button === Qt.LeftButton) {
                            if (modelData && modelData.activate) {
                                modelData.activate();
                            }
                        }
                    }

                    onPressed: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            // context menu logic (optional)
                        }
                    }
                }

                Rectangle {
                    visible: isActive
                    width: 4
                    height: 4
                    radius: 2
                    color: Theme.onAccent
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottomMargin: -6
                }
            }
        }
    }
}
