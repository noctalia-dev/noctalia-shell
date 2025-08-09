import QtQuick
import Quickshell
import qs.Settings

Item {
    id: buttonRoot
    property Item barBackground
    property var screen
    width: iconText.implicitWidth + 0
    height: iconText.implicitHeight + 0

    property color hoverColor: Theme.rippleEffect
    property real hoverOpacity: 0.0
    property bool isActive: mouseArea.containsMouse || (sidebarPopup && sidebarPopup.visible)

    property var sidebarPopup

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (sidebarPopup.visible) {
                sidebarPopup.hidePopup();
            } else {
                sidebarPopup.showAt();
            }
        }
        onEntered: buttonRoot.hoverOpacity = 0.18
        onExited: buttonRoot.hoverOpacity = 0.0
    }

    Rectangle {
        anchors.fill: parent
        color: hoverColor
        opacity: isActive ? 0.18 : hoverOpacity
        radius: height / 2
        z: 0
        visible: (isActive ? 0.18 : hoverOpacity) > 0.01
    }

    Text {
        id: iconText
        text: "dashboard"
        font.family: isActive ? "Material Symbols Rounded" : "Material Symbols Outlined"
        font.pixelSize: 16 * Theme.scale(screen)
        color: sidebarPopup.visible ? Theme.accentPrimary : Theme.textPrimary
        anchors.centerIn: parent
        z: 1
    }

    Behavior on hoverOpacity {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutQuad
        }
    }
}
