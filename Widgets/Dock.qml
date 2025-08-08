import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Settings
import qs.Components


Variants {
    model: Quickshell.screens

    Item {
        property var modelData  

        // Auto-hide properties
        property bool autoHide: true
        property bool hidden: true
        property int hideDelay: 500
        property int showDelay: 100
        property int hideAnimationDuration: 200
        property int showAnimationDuration: 150
        property int peekHeight: 2
        property int fullHeight: dockContainer.height

        // Track hover state
        property bool dockHovered: false
        property bool anyAppHovered: false

        // Context menu properties
        property bool contextMenuVisible: false
        property var contextMenuTarget: null
        property var contextMenuToplevel: null

        PanelWindow {

            id: dockWindow
            visible: Settings.settings.showDock && 
                    (Settings.settings.dockMonitors.includes(modelData.name) ||
                                        (Settings.settings.dockMonitors.length === 0))
            screen: modelData
            exclusionMode: ExclusionMode.Ignore
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            focusable: false
            color: "transparent"
            implicitHeight: 43

            // Timer for auto-hide delay
            Timer {
                id: hideTimer
                interval: hideDelay
                onTriggered: if (autoHide && !dockHovered && !anyAppHovered && !contextMenuVisible) hidden = true
            }

            // Timer for show delay
            Timer {
                id: showTimer
                interval: showDelay
                onTriggered: hidden = false
            }

            // Behavior for smooth hide/show animations
            Behavior on margins.bottom {
                NumberAnimation {
                    duration: hidden ? hideAnimationDuration : showAnimationDuration
                    easing.type: Easing.InOutQuad
                }
            }

            // Mouse area at screen bottom to detect entry and keep dock visible
            MouseArea {
                id: screenEdgeMouseArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 10 * Theme.scale(dockWindow.screen)
                hoverEnabled: true
                propagateComposedEvents: true

                onEntered: if (autoHide && hidden) showTimer.start()
                onExited: if (autoHide && !hidden && !dockHovered && !anyAppHovered && !contextMenuVisible) hideTimer.start()
            }

            margins.bottom: hidden ? -(fullHeight - peekHeight) : 0

            Rectangle {
                id: dockContainer
                width: dock.width + 40
                height: Settings.settings.taskbarIconSize + 20
                topLeftRadius: 16
                topRightRadius: 16
                color: Theme.backgroundSecondary
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom

                MouseArea {
                    id: dockMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    propagateComposedEvents: true

                    onEntered: {
                        dockHovered = true
                        if (autoHide) {
                            showTimer.stop()
                            hideTimer.stop()
                            hidden = false
                        }
                    }
                    onExited: {
                        dockHovered = false
                        if (autoHide && !anyAppHovered && !contextMenuVisible) hideTimer.start()
                    }
                }

                Item {
                    id: dock
                    width: runningAppsRow.width
                    height: parent.height - 10
                    anchors.centerIn: parent

                    StyledTooltip { id: styledTooltip }

                    function getAppIcon(toplevel: Toplevel): string {
                        if (!toplevel) return "";
                        let icon = Quickshell.iconPath(toplevel.appId?.toLowerCase(), true);
                        if (!icon) icon = Quickshell.iconPath(toplevel.appId, true);
                        if (!icon) icon = Quickshell.iconPath(toplevel.title?.toLowerCase(), true);
                        if (!icon) icon = Quickshell.iconPath(toplevel.title, true);
                        return icon || Quickshell.iconPath("application-x-executable", true);
                    }

                    Row {
                        id: runningAppsRow
                        spacing: 12
                        height: parent.height
                        anchors.centerIn: parent

                        Repeater {
                            model: ToplevelManager ? ToplevelManager.toplevels : null

                            delegate: Rectangle {
                                id: appButton
                                width: Settings.settings.taskbarIconSize + 8
                                height: Settings.settings.taskbarIconSize + 8
                                radius: Math.max(6, Settings.settings.taskbarIconSize * 0.3)
                                color: isActive ? Theme.accentPrimary : (hovered ? Theme.surfaceVariant : "transparent")
                                border.color: isActive ? Qt.darker(Theme.accentPrimary, 1.2) : "transparent"
                                border.width: 1

                                property bool isActive: ToplevelManager.activeToplevel && ToplevelManager.activeToplevel === modelData
                                property bool hovered: appMouseArea.containsMouse
                                property string appId: modelData ? modelData.appId : ""
                                property string appTitle: modelData ? modelData.title : ""

                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }

                                IconImage {
                                    id: appIcon
                                    width: Math.max(20, Settings.settings.taskbarIconSize * 0.75)
                                    height: Math.max(20, Settings.settings.taskbarIconSize * 0.75)
                                    anchors.centerIn: parent
                                    source: dock.getAppIcon(modelData)
                                    visible: source.toString() !== ""
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !appIcon.visible
                                    text: appButton.appId ? appButton.appId.charAt(0).toUpperCase() : "?"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.max(14, Settings.settings.taskbarIconSize * 0.5)
                                    font.bold: true
                                    color: appButton.isActive ? Theme.onAccent : Theme.textPrimary
                                }

                                MouseArea {
                                    id: appMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                                    onEntered: {
                                        anyAppHovered = true
                                        if (!contextMenuVisible) {
                                            styledTooltip.text = appTitle || appId;
                                            styledTooltip.targetItem = appButton;
                                            styledTooltip.positionAbove = true;
                                            styledTooltip.tooltipVisible = true;
                                        }
                                        if (autoHide) {
                                            showTimer.stop()
                                            hideTimer.stop()
                                            hidden = false
                                        }
                                    }
                                    onExited: {
                                        anyAppHovered = false
                                        if (!contextMenuVisible) {
                                            styledTooltip.tooltipVisible = false;
                                        }
                                        if (autoHide && !dockHovered && !contextMenuVisible) hideTimer.start()
                                    }
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.MiddleButton && modelData?.close) {
                                            modelData.close();
                                        }
                                        if (mouse.button === Qt.LeftButton && modelData?.activate) {
                                            modelData.activate();
                                        }
                                        if (mouse.button === Qt.RightButton) {
                                            styledTooltip.tooltipVisible = false;
                                            contextMenuTarget = appButton;
                                            contextMenuToplevel = modelData;
                                            contextMenuVisible = true;
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: isActive
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: Theme.onAccent
                                    anchors.bottom: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottomMargin: -8
                                }
                            }
                        }
                    }
                }
            }

            // Context Menu
            PanelWindow {
                id: contextMenuWindow
                visible: contextMenuVisible
                screen: dockWindow.screen
                exclusionMode: ExclusionMode.Ignore
                anchors.bottom: true
                anchors.left: true
                anchors.right: true
                color: "transparent"
                focusable: false

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        contextMenuVisible = false;
                        contextMenuTarget = null;
                        contextMenuToplevel = null;
                        hidden = true; // Hide dock when context menu closes
                    }
                }

                Rectangle {
                    id: contextMenuContainer
                    width: 80
                    height: contextMenuColumn.height + 0
                    radius: 16
                    color: Theme.backgroundPrimary
                    border.color: Theme.outline
                    border.width: 1

                    x: {
                        if (!contextMenuTarget) return 0;
                        // Get position relative to screen
                        const pos = contextMenuTarget.mapToItem(null, 0, 0);
                        // Center horizontally above the icon
                        let xPos = pos.x + (contextMenuTarget.width - width) / 2;
                        // Constrain to screen edges
                        return Math.max(0, Math.min(xPos, dockWindow.width - width));
                    }

                    y: {
                        if (!contextMenuTarget) return 0;
                        // Position above the dock
                        const pos = contextMenuTarget.mapToItem(null, 0, 0);
                        return pos.y - height + 32;
                    }

                    Column {
                        id: contextMenuColumn
                        anchors.centerIn: parent
                        spacing: 4
                        width: parent.width


                        Rectangle {
                            width: parent.width
                            height: 32
                            radius: 16
                            color: closeMouseArea.containsMouse ? Theme.surfaceVariant : "transparent"
                            border.color: Theme.outline
                            border.width: 1

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "close"
                                    font.family: "Material Symbols Outlined"
                                    font.pixelSize: 14 * Theme.scale(dockWindow.screen)
                                    color: Theme.textPrimary
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Close"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 14 * Theme.scale(dockWindow.screen)
                                    color: Theme.textPrimary
                                }
                            }

                            MouseArea {
                                id: closeMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    if (contextMenuToplevel?.close) contextMenuToplevel.close();
                                    contextMenuVisible = false;
                                    hidden = true;
                                }
                            }
                        }
                    }

                    // Animation
                    scale: contextMenuVisible ? 1 : 0.9
                    opacity: contextMenuVisible ? 1 : 0
                    transformOrigin: Item.Bottom

                    Behavior on scale {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutBack
                        }
                    }

                    Behavior on opacity {
                        NumberAnimation { duration: 100 }
                    }
                }
            }
        }

    }
}
