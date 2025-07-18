import QtQuick 
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import qs.Settings
import qs.Components
import qs.Services

Rectangle {
    id: musicCard
    width: 360
    height: 250
    color: "transparent"

    Rectangle {
        id: card
        anchors.fill: parent
        color: Theme.surface
        radius: 18

        // Show fallback UI if no player is available
        Item {
            width: parent.width
            height: parent.height
            visible: !MusicManager.currentPlayer

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16

                Text {
                    text: "music_note"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: Theme.fontSizeHeader
                    color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: MusicManager.hasPlayer ? "No controllable player selected" : "No music player detected"
                    color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // Main player UI
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            visible: !!MusicManager.currentPlayer

            // Album art and spectrum
            RowLayout {
                spacing: 12
                Layout.fillWidth: true

                // Album art with spectrum
                Item {
                    id: albumArtContainer
                    width: 96; height: 96 // enough for spectrum and art (will adjust if needed)
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                    // Spectrum visualizer
                    CircularSpectrum {
                        id: spectrum
                        values: MusicManager.cavaValues
                        anchors.centerIn: parent
                        innerRadius: 30 // just outside 60x60 album art
                        outerRadius: 48 // how far bars extend
                        fillColor: Theme.accentPrimary
                        strokeColor: Theme.accentPrimary
                        strokeWidth: 0
                        z: 0
                    }

                    // Album art image
                    Rectangle {
                        id: albumArtwork
                        width: 60; height: 60
                        anchors.centerIn: parent
                        radius: 30 // circle
                        color: Qt.darker(Theme.surface, 1.1)
                        border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3)
                        border.width: 1

                        Image {
                            id: albumArt
                            anchors.fill: parent
                            anchors.margins: 2
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            cache: false
                            asynchronous: true
                            sourceSize.width: 60
                            sourceSize.height: 60
                            source: MusicManager.trackArtUrl
                            visible: source.toString() !== ""

                            // Rounded corners using layer
                            layer.enabled: true
                            layer.effect: OpacityMask {
                                cached: true
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
                            text: "album"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: Theme.fontSizeBody
                            color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.4)
                            visible: !albumArt.visible
                        }
                    }
                }

                // Track metadata
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: MusicManager.trackTitle
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                        elide: Text.ElideRight
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        Layout.fillWidth: true
                    }

                    Text {
                        text: MusicManager.trackArtist
                        color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.8)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: MusicManager.trackAlbum
                        color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            // Progress bar
            Rectangle {
                id: progressBarBackground
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.15)
                Layout.fillWidth: true

                property real progressRatio: Math.min(1, MusicManager.trackLength > 0 ? 
                                           (MusicManager.currentPosition / MusicManager.trackLength) : 0)

                Rectangle {
                    id: progressFill
                    width: progressBarBackground.progressRatio * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accentPrimary

                    Behavior on width {
                        NumberAnimation { duration: 200 }
                    }
                }

                // Interactive progress handle
                Rectangle {
                    id: progressHandle
                    width: 12
                    height: 12
                    radius: 6
                    color: Theme.accentPrimary
                    border.color: Qt.lighter(Theme.accentPrimary, 1.3)
                    border.width: 1

                    x: Math.max(0, Math.min(parent.width - width, progressFill.width - width/2))
                    anchors.verticalCenter: parent.verticalCenter

                    visible: MusicManager.trackLength > 0
                    scale: progressMouseArea.containsMouse || progressMouseArea.pressed ? 1.2 : 1.0

                    Behavior on scale {
                        NumberAnimation { duration: 150 }
                    }
                }

                // Mouse area for seeking
                MouseArea {
                    id: progressMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: MusicManager.trackLength > 0 && MusicManager.canSeek

                    onClicked: function(mouse) {
                        let ratio = mouse.x / width
                        MusicManager.seekByRatio(ratio)
                    }

                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            let ratio = Math.max(0, Math.min(1, mouse.x / width))
                            MusicManager.seekByRatio(ratio)
                        }
                    }
                }
            }

            // Media controls
            RowLayout {
                spacing: 4
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter

                // Previous button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: previousButton.containsMouse ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.2) : Qt.darker(Theme.surface, 1.1)
                    border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3)
                    border.width: 1

                    MouseArea {
                        id: previousButton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: MusicManager.canGoPrevious
                        onClicked: MusicManager.previous()
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "skip_previous"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: Theme.fontSizeCaption
                        color: previousButton.enabled ? Theme.accentPrimary : Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    }
                }

                // Play/Pause button
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: playButton.containsMouse ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.2) : Qt.darker(Theme.surface, 1.1)
                    border.color: Theme.accentPrimary
                    border.width: 2

                    MouseArea {
                        id: playButton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: MusicManager.canPlay || MusicManager.canPause
                        onClicked: MusicManager.playPause()
                    }

                    Text {
                        anchors.centerIn: parent
                        text: MusicManager.isPlaying ? "pause" : "play_arrow"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: Theme.fontSizeBody
                        color: playButton.enabled ? Theme.accentPrimary : Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    }
                }

                // Next button
                Rectangle {
                    width: 28
                    height: 28
                    radius: 14
                    color: nextButton.containsMouse ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.2) : Qt.darker(Theme.surface, 1.1)
                    border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3)
                    border.width: 1

                    MouseArea {
                        id: nextButton
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: MusicManager.canGoNext
                        onClicked: MusicManager.next()
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "skip_next"
                        font.family: "Material Symbols Outlined"
                        font.pixelSize: Theme.fontSizeCaption
                        color: nextButton.enabled ? Theme.accentPrimary : Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    }
                }
            }
        }
    }
} 