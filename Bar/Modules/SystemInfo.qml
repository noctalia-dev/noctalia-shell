import QtQuick
import Quickshell
import qs.Settings
import qs.Services

Row {
    id: layout

    property var screen: (typeof modelData !== 'undefined' ? modelData : null)
    
    spacing: 10
    visible: Settings.settings.showSystemInfoInBar

    width: Math.floor(cpuUsageLayout.width + cpuTempLayout.width + memoryUsageLayout.width + (2 * 10))

    Row {
        id: cpuUsageLayout
        spacing: 6

        Text {
            id: cpuUsageIcon
            font.family: "Material Symbols Outlined"
            font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
            text: "speed"
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.accentPrimary
        }

        Text {
            id: cpuUsageText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall * Theme.scale(screen)
            color: Theme.textPrimary
            text: Sysinfo.cpuUsageStr
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // CPU Temperature Component
    Row {
        id: cpuTempLayout
        spacing: 3
        Text {
            font.family: "Material Symbols Outlined"
            font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
            text: "thermometer"
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.accentPrimary
        }

        Text {
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall * Theme.scale(screen)
            color: Theme.textPrimary
            text: Sysinfo.cpuTempStr
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Memory Usage Component
    Row {
        id: memoryUsageLayout
        spacing: 3
        Text {
            font.family: "Material Symbols Outlined"
            font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
            text: "memory"
            color: Theme.accentPrimary
            verticalAlignment: Text.AlignVCenter
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall * Theme.scale(screen)
            color: Theme.textPrimary
            text: Sysinfo.memoryUsageStr
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
