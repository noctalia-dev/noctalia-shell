import QtQuick
import qs.Settings

Rectangle {
    color: "transparent"
    width: rowItem.implicitWidth
    height: rowItem.implicitHeight

    Row {
        id: rowItem
        spacing: 4
        anchors.centerIn: parent

        Text {
            id: timeText
            text: Qt.formatTime(new Date(), "hh:mm")
            font.family: Theme.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.textPrimary
        }

        Text {
            text: "|"
            font.family: Theme.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.textPrimary
        }

        Text {
            id: dateText
            text: Qt.formatDate(new Date(), "dd.MM.yyyy")
            font.family: Theme.fontFamily
            font.weight: Font.Bold
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.textPrimary
        }

        Timer {
            interval: 60000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                timeText.text = Qt.formatTime(new Date(), "hh:mm")
                dateText.text = Qt.formatDate(new Date(), "dd.MM.yyyy")
            }
        }
    }
}
