import QtQuick 
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import qs.Settings
import qs.Services

PanelWindow {
    id: wallpaperPanelModal
    implicitWidth: 480
    implicitHeight: 780
    visible: false
    color: "transparent"
    anchors.top: true
    anchors.right: true
    margins.right: 0
    margins.top: 0
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property var wallpapers: []

    Connections {
        target: WallpaperManager
        function onWallpaperListChanged() {
            wallpapers = WallpaperManager.wallpaperList
        }
    }

    onVisibleChanged: {
        if (wallpaperPanelLoader.active) {
            wallpapers = WallpaperManager.wallpaperList
        } else {
            wallpapers = []
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.backgroundPrimary
        radius: 24
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                spacing: 20
                Layout.preferredHeight: 48
                Text {
                    text: "image"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: Theme.fontSizeHeader
                    color: Theme.accentPrimary
                }
                Text {
                    text: "Wallpapers"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeHeader
                    font.bold: true
                    color: Theme.textPrimary
                    Layout.fillWidth: true
                }
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: closeButtonArea.containsMouse ? Theme.accentPrimary : "transparent"
                    border.color: Theme.accentPrimary
                    border.width: 1
                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: closeButtonArea.containsMouse ? "Material Symbols Rounded" : "Material Symbols Outlined"
                        font.pixelSize: Theme.fontSizeBody
                        color: closeButtonArea.containsMouse ? Theme.onAccent : Theme.accentPrimary
                    }
                    MouseArea {
                        id: closeButtonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: wallpaperPanelLoader.active = false;
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.outline
                opacity: 0.12
            }
            // Wallpaper grid area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                anchors.topMargin: 16
                anchors.bottomMargin: 16
                anchors.leftMargin: 0
                anchors.rightMargin: 0
                anchors.margins: 0
                clip: true
                ScrollView {
                    id: scrollView
                    anchors.fill: parent
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    GridView {
                        id: wallpaperGrid
                        anchors.fill: parent
                        cellWidth: Math.max(120, (scrollView.width / 3) - 12)
                        cellHeight: cellWidth * 0.6
                        model: wallpapers
                        cacheBuffer: 32
                        leftMargin: 8
                        rightMargin: 8
                        topMargin: 8
                        bottomMargin: 8
                        delegate: Item {
                            width: wallpaperGrid.cellWidth - 8
                            height: wallpaperGrid.cellHeight - 8
                            ClippingRectangle {
                                id: wallpaperItem
                                anchors.fill: parent
                                anchors.margins: 4
                                color: Qt.darker(Theme.backgroundPrimary, 1.1)
                                radius: 12
                                border.color: Settings.settings.currentWallpaper === modelData ? Theme.accentPrimary : Theme.outline
                                border.width: Settings.settings.currentWallpaper === modelData ? 3 : 1
                                Image {
                                    id: wallpaperImage
                                    anchors.fill: parent
                                    source: modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                    smooth: true
                                    mipmap: true
                                    // Limit memory usage
                                    sourceSize.width: 480
                                    sourceSize.height: 270
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    color: Theme.textPrimary
                                    opacity: (wallpaperImage.status == Image.Ready) ? 0.0 : 1.0
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 500
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        WallpaperManager.changeWallpaper(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
