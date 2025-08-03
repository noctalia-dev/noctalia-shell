import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.Settings
import QtQuick.Effects

Item {
    anchors.fill: parent

    anchors.leftMargin: 2
    anchors.rightMargin: 2
    anchors.topMargin: 2
    anchors.bottomMargin: 2

    IconImage {
        id: avatarImage
        anchors.fill: parent
        anchors.margins: 2
        source: "file://" + Settings.settings.profileImage
        visible: false
        asynchronous: true
        backer.fillMode: Image.PreserveAspectCrop
    }

    MultiEffect {
        anchors.fill: parent
        source: avatarImage
        maskEnabled: true
        maskSource: mask
        visible: Settings.settings.profileImage !== ""
    }

    Item {
        id: mask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.fill: parent
            radius: avatarImage.width / 2
        }
    }

    // Fallback icon
    Text {
        anchors.centerIn: parent
        text: "person"
        font.family: "Material Symbols Outlined"
        font.pixelSize: 24
        color: Theme.onAccent
        visible: Settings.settings.profileImage === undefined || Settings.settings.profileImage === ""
        z: 0
    }
}
