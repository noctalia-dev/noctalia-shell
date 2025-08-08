import QtQuick 
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Widgets
import QtQuick.Effects
import qs.Settings
import qs.Services
import qs.Components

Item {
    id: mediaControl
    width: visible ? mediaRow.width : 0
    height: 36 * Theme.scale(Screen)
    visible: Settings.settings.showMediaInBar && MusicManager.currentPlayer

    RowLayout {
        id: mediaRow
        height: parent.height
        spacing: 8

        Item {
            id: albumArtContainer
            width: 24 * Theme.scale(Screen)
            height: 24 * Theme.scale(Screen)
            Layout.alignment: Qt.AlignVCenter

            // Circular spectrum visualizer
            CircularSpectrum {
                id: spectrum
                values: MusicManager.cavaValues
                anchors.centerIn: parent
                innerRadius: 10 * Theme.scale(Screen)
                outerRadius: 18 * Theme.scale(Screen)
                fillColor: Theme.accentPrimary
                strokeColor: Theme.accentPrimary
                strokeWidth: 0
                z: 0
            }

            // Album art image
            Rectangle {
                id: albumArtwork
                width: 20 * Theme.scale(Screen)
                height: 20 * Theme.scale(Screen)
                anchors.centerIn: parent
                radius: 12 * Theme.scale(Screen) // circle
                color: Qt.darker(Theme.surface, 1.1)
                border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3)
                border.width: 1
                z: 1

                Image {
                    id: albumArt
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                    cache: false
                    asynchronous: true
                    source: MusicManager.trackArtUrl
                    visible: source.toString() !== ""

                    // Rounded corners using layer
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: Rectangle {
                            width: albumArt.width
                            height: albumArt.height
                            radius: albumArt.width / 2 // circle
                            visible: false
                        }
                    }
                }

                // Fallback icon
                Text {
                    anchors.centerIn: parent
                    text: "music_note"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 14 * Theme.scale(Screen)
                    color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.4)
                    visible: !albumArt.visible
                }

                // Play/Pause overlay (only visible on hover)
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.rgba(0, 0, 0, 0.5)
                    visible: playButton.containsMouse
                    z: 2

                    Text {
                        anchors.centerIn: parent
                        text: MusicManager.isPlaying ? "pause" : "play_arrow"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: 14 * Theme.scale(Screen)
                        color: "white"
                    }
                }

                MouseArea {
                    id: playButton
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    enabled: MusicManager.canPlay || MusicManager.canPause
                    onClicked: MusicManager.playPause()
                }
            }
        }

        // Track info
        Text {
            text: MusicManager.trackTitle + " - " + MusicManager.trackArtist
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: 12 * Theme.scale(Screen)
            elide: Text.ElideRight
            Layout.maximumWidth: 300
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
