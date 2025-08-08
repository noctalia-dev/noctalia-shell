import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Settings
import qs.Components

ColumnLayout {
    id: root
    spacing: 24

    Text {
        text: "Coming soon..."
        font.pixelSize: 16
        font.bold: true
        color: Theme.textPrimary
        Layout.alignment: Qt.AlignCenter
        Layout.topMargin: 32
    }
}