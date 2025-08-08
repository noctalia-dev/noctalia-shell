import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Components
import qs.Services
import qs.Settings

Rectangle {
    id: wallpaperOverlay
    focus: true

    // Function to show the overlay and load wallpapers
    function show() {
        // Ensure wallpapers are loaded
        WallpaperManager.loadWallpapers();
        wallpaperOverlay.visible = true;
        wallpaperOverlay.forceActiveFocus();
    }

    // Function to hide the overlay
    function hide() {
        wallpaperOverlay.visible = false;
    }

    color: Theme.backgroundPrimary
    visible: false
    z: 1000

    // Handle escape key to close
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
            wallpaperOverlay.hide();
            event.accepted = true;
        }
    }

    // Click outside to close
    MouseArea {
        anchors.fill: parent
        onClicked: {
            wallpaperOverlay.hide();
        }
    }

    // Content area that stops event propagation
    MouseArea {
        // Stop event propagation

        anchors.fill: parent
        anchors.margins: 24
        onClicked: {
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0



            // Wallpaper Grid
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ScrollView {
                    anchors.fill: parent
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    GridView {
                        id: wallpaperGrid

                        anchors.fill: parent
                        cellWidth: Math.max(120 * Theme.scale(Screen), (parent.width / 3) - 12 * Theme.scale(Screen))
                        cellHeight: cellWidth * 0.6
                        model: WallpaperManager.wallpaperList
                        cacheBuffer: 64
                        leftMargin: 8
                        rightMargin: 8
                        topMargin: 8
                        bottomMargin: 8

                        delegate: Item {
                            width: wallpaperGrid.cellWidth - 8 * Theme.scale(Screen)
                            height: wallpaperGrid.cellHeight - 8 * Theme.scale(Screen)

                            Rectangle {
                                id: wallpaperItem

                                anchors.fill: parent
                                anchors.margins: 3
                                color: Theme.surface
                                radius: 12 * Theme.scale(Screen)
                                border.color: Settings.settings.currentWallpaper === modelData ? Theme.accentPrimary : Theme.outline
                                border.width: 2 * Theme.scale(Screen)

                                Image {
                                    id: wallpaperImage

                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    smooth: true
                                    mipmap: true
                                    sourceSize.width: Math.min(width, 480 * Theme.scale(Screen))
                                    sourceSize.height: Math.min(height, 270 * Theme.scale(Screen))
                                    opacity: (wallpaperImage.status == Image.Ready) ? 1 : 0
                                    // Apply circular mask for rounded corners
                                    layer.enabled: true

                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 300
                                            easing.type: Easing.OutCubic
                                        }

                                    }

                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: mask
                                    }

                                }

                                Item {
                                    id: mask

                                    anchors.fill: wallpaperImage
                                    layer.enabled: true
                                    visible: false

                                    Rectangle {
                                        width: wallpaperImage.width
                                        height: wallpaperImage.height
                                        radius: 12 * Theme.scale(Screen)
                                    }

                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
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
