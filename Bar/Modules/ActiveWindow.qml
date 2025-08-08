import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Components
import qs.Settings

PanelWindow {
    id: activeWindowPanel

    // Lower case "screen" from modelData
    property int barHeight: 36 * Theme.scale(screen)

    screen: (typeof modelData !== 'undefined' ? modelData : null)
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.left: true
    anchors.right: true
    focusable: false
    margins.top: barHeight
    visible: Settings.settings.showActiveWindow && !activeWindowWrapper.finallyHidden 
    implicitHeight: activeWindowTitleContainer.height
    implicitWidth: 0
    color: "transparent"

    function getIcon() {
        var icon = Quickshell.iconPath(ToplevelManager.activeToplevel.appId.toLowerCase(), true);
        if (!icon) {
            icon = Quickshell.iconPath(ToplevelManager.activeToplevel.appId, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(ToplevelManager.activeToplevel.title, true);
        }
        if (!icon) {
            icon = Quickshell.iconPath(ToplevelManager.activeToplevel.title.toLowerCase(), "application-x-executable");
        }

        return icon;
    }

    Item {
        id: activeWindowWrapper
        width: parent.width
        property int fullHeight: activeWindowTitleContainer.height
        property bool shouldShow: false
        property bool finallyHidden: false

        Timer {
            id: visibilityTimer
            interval: 1500
            running: false
            onTriggered: {
                activeWindowWrapper.shouldShow = false;
                hideTimer.restart();
            }
        }

        Timer {
            id: hideTimer
            interval: 300
            running: false
            onTriggered: {
                activeWindowWrapper.finallyHidden = true;
            }
        }

        Connections {
            target: ToplevelManager
            function onActiveToplevelChanged() {
                if (ToplevelManager.activeToplevel?.appId) {
                    activeWindowWrapper.shouldShow = true;
                    activeWindowWrapper.finallyHidden = false;
                    visibilityTimer.restart();
                } else {
                    activeWindowWrapper.shouldShow = false;
                    hideTimer.restart();
                    visibilityTimer.stop();
                }
            }
        }

        y: shouldShow ? 0 : -activeWindowPanel.barHeight
        height: shouldShow ? fullHeight : 1
        opacity: shouldShow ? 1 : 0
        clip: true

        Behavior on height {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutQuad
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutQuad
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: 250
            }
        }

        Rectangle {
            id: activeWindowTitleContainer
            color: "transparent"


            width: Math.min(barBackground.width - 200, activeWindowTitle.implicitWidth + (Settings.settings.showActiveWindowIcon ? 28 : 22)) + 16
            height: activeWindowTitle.implicitHeight + 12

            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                id: innerRect

                bottomLeftRadius: Math.max(0, width / 2)
                bottomRightRadius: Math.max(0, width / 2)
                color: Theme.backgroundPrimary
                anchors {
                    fill: parent
                    leftMargin: 0
                    rightMargin: 0
                    topMargin: -1
                    bottomMargin: 0
                }
            

                border.color: Theme.outline || "#444";
                border.width: 1;

                IconImage {
                    id: icon
                    width: 12
                    height: 12
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    source: ToplevelManager?.activeToplevel ? getIcon() : ""
                    visible: Settings.settings.showActiveWindowIcon
                    anchors.verticalCenterOffset: -3

                }

                Text {
                    id: activeWindowTitle
                    text: ToplevelManager?.activeToplevel?.title && ToplevelManager?.activeToplevel?.title.length > 60 ? ToplevelManager?.activeToplevel?.title.substring(0, 60) + "..." : ToplevelManager?.activeToplevel?.title || ""
                    font.pixelSize: 12 * Theme.scale(Screen)
                    color: Theme.textSecondary
                    anchors.left: icon.right
                    anchors.leftMargin: Settings.settings.showActiveWindowIcon ? 4 : 6
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -3
                    horizontalAlignment: Settings.settings.showActiveWindowIcon ? Text.AlignRight : Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    maximumLineCount: 1
                }
            }
        }
    }
}
