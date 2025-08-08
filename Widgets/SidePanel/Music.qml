import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Components
import qs.Services
import qs.Settings

Rectangle {
    id: musicCard

    property var screen: (typeof modelData !== 'undefined' ? modelData : null)

    color: "transparent"

    Rectangle {
        id: card

        anchors.fill: parent
        color: Theme.surface
        radius: 18 * Theme.scale(screen)

        // Show fallback UI if no player is available
        Item {
            width: parent.width
            height: parent.height
            visible: !MusicManager.currentPlayer

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16 * Theme.scale(screen)

                Text {
                    text: "music_note"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: Theme.fontSizeHeader * Theme.scale(screen)
                    color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: MusicManager.hasPlayer ? "No controllable player selected" : "No music player detected"
                    color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.6)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall * Theme.scale(screen)
                    Layout.alignment: Qt.AlignHCenter
                }

            }

        }

        // Main player UI
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18 * Theme.scale(screen)
            spacing: 12 * Theme.scale(screen)
            visible: !!MusicManager.currentPlayer

            // Player selector
            ComboBox {
                id: playerSelector

                Layout.fillWidth: true
                Layout.preferredHeight: 40 * Theme.scale(screen)
                visible: MusicManager.getAvailablePlayers().length > 1
                model: MusicManager.getAvailablePlayers()
                textRole: "identity"
                currentIndex: MusicManager.selectedPlayerIndex
                onActivated: {
                    MusicManager.selectedPlayerIndex = index;
                    MusicManager.updateCurrentPlayer();
                }

                background: Rectangle {
                    implicitWidth: 120 * Theme.scale(screen)
                    implicitHeight: 40 * Theme.scale(screen)
                    color: Theme.surfaceVariant
                    border.color: playerSelector.activeFocus ? Theme.accentPrimary : Theme.outline
                    border.width: 1 * Theme.scale(screen)
                    radius: 16 * Theme.scale(screen)
                }

                contentItem: Text {
                    leftPadding: 12 * Theme.scale(screen)
                    rightPadding: playerSelector.indicator.width + playerSelector.spacing
                    text: playerSelector.displayText
                    font.pixelSize: 13 * Theme.scale(screen)
                    color: Theme.textPrimary
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Text {
                    x: playerSelector.width - width - 12 * Theme.scale(screen)
                    y: playerSelector.topPadding + (playerSelector.availableHeight - height) / 2
                    text: "arrow_drop_down"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: 24 * Theme.scale(screen)
                    color: Theme.textPrimary
                }

                popup: Popup {
                    y: playerSelector.height
                    width: playerSelector.width
                    implicitHeight: contentItem.implicitHeight
                    padding: 1 * Theme.scale(screen)

                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: playerSelector.popup.visible ? playerSelector.delegateModel : null
                        currentIndex: playerSelector.highlightedIndex

                        ScrollIndicator.vertical: ScrollIndicator {
                        }

                    }

                    background: Rectangle {
                        color: Theme.surfaceVariant
                        border.color: Theme.outline
                        border.width: 1 * Theme.scale(screen)
                        radius: 16
                    }

                }

                delegate: ItemDelegate {
                    width: playerSelector.width
                    highlighted: playerSelector.highlightedIndex === index

                    contentItem: Text {
                        text: modelData.identity
                        font.pixelSize: 13 * Theme.scale(screen)
                        color: Theme.textPrimary
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    background: Rectangle {
                        color: highlighted ? Theme.accentPrimary.toString().replace(/#/, "#1A") : "transparent"
                    }

                }

            }

            // Album art with spectrum visualizer
            RowLayout {
                spacing: 12 * Theme.scale(screen)
                Layout.fillWidth: true

                // Album art container with circular spectrum overlay
                Item {
                    id: albumArtContainer

                    width: 96 * Theme.scale(screen)
                    height: 96 * Theme.scale(screen) // enough for spectrum and art (will adjust if needed)
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                    // Circular spectrum visualizer around album art
                    CircularSpectrum {
                        id: spectrum

                        values: MusicManager.cavaValues
                        anchors.centerIn: parent
                        innerRadius: 30 * Theme.scale(screen) // Position just outside 60x60 album art
                        outerRadius: 48 * Theme.scale(screen) // Extend bars outward from album art
                        fillColor: Theme.accentPrimary
                        strokeColor: Theme.accentPrimary
                        strokeWidth: 0 * Theme.scale(screen)
                        z: 0
                    }

                    // Album art image
                    Rectangle {
                        id: albumArtwork

                        width: 60 * Theme.scale(screen)
                        height: 60 * Theme.scale(screen)
                        anchors.centerIn: parent
                        radius: width * 0.5
                        color: Qt.darker(Theme.surface, 1.1)
                        border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3)
                        border.width: 1 * Theme.scale(screen)

                        Image {
                            id: albumArt

                            anchors.fill: parent
                            anchors.margins: 2 * Theme.scale(screen)
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                            cache: false
                            asynchronous: true
                            sourceSize.width: 60 * Theme.scale(screen)
                            sourceSize.height: 60 * Theme.scale(screen)
                            source: MusicManager.trackArtUrl
                            visible: source.toString() !== ""
                            // Apply circular mask for rounded corners
                            layer.enabled: true

                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: mask
                            }

                        }

                        Item {
                            id: mask

                            anchors.fill: albumArt
                            layer.enabled: true
                            visible: false

                            Rectangle {
                                width: albumArt.width
                                height: albumArt.height
                                radius: albumArt.width / 2 // circle
                            }

                        }

                        // Fallback icon when no album art available
                        Text {
                            anchors.centerIn: parent
                            text: "album"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
                            color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.4)
                            visible: !albumArt.visible
                        }

                    }

                }

                // Track metadata
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4 * Theme.scale(screen)

                    Text {
                        text: MusicManager.trackTitle
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall * Theme.scale(screen)
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
                        font.pixelSize: Theme.fontSizeCaption * Theme.scale(screen)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: MusicManager.trackAlbum
                        color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.6)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption * Theme.scale(screen)
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                }

            }

            // Progress bar
            Rectangle {
                id: progressBarBackground

                property real progressRatio: {
                    if (!MusicManager.currentPlayer || !MusicManager.isPlaying || MusicManager.trackLength <= 0)
                        return 0;

                    return Math.min(1, MusicManager.currentPosition / MusicManager.trackLength);
                }

                width: parent.width
                height: 6 * Theme.scale(screen)
                radius: 3
                color: Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.15)
                Layout.fillWidth: true

                Rectangle {
                    id: progressFill

                    width: progressBarBackground.progressRatio * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accentPrimary

                    Behavior on width {
                        NumberAnimation {
                            duration: 200
                        }

                    }

                }

                // Interactive progress handle
                Rectangle {
                    id: progressHandle

                    width: 12 * Theme.scale(screen)
                    height: 12 * Theme.scale(screen)
                    radius: width * 0.5
                    color: Theme.accentPrimary
                    border.color: Qt.lighter(Theme.accentPrimary, 1.3)
                    border.width: 1 * Theme.scale(screen)
                    x: Math.max(0, Math.min(parent.width - width, progressFill.width - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    visible: MusicManager.trackLength > 0
                    scale: progressMouseArea.containsMouse || progressMouseArea.pressed ? 1.2 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 150
                        }

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
                        let ratio = mouse.x / width;
                        MusicManager.seekByRatio(ratio);
                    }
                    onPositionChanged: function(mouse) {
                        if (pressed) {
                            let ratio = Math.max(0, Math.min(1, mouse.x / width));
                            MusicManager.seekByRatio(ratio);
                        }
                    }
                }

            }

            // Media controls
            RowLayout {
                spacing: 4 * Theme.scale(screen)
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter

                // Previous button
                Rectangle {
                    width: 28 * Theme.scale(screen)
                    height: 28 * Theme.scale(screen)
                    radius: width * 0.5
                    color: previousButton.containsMouse ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.2) : Qt.darker(Theme.surface, 1.1)
                    border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3)
                    border.width: 1 * Theme.scale(screen)

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
                        font.pixelSize: Theme.fontSizeCaption * Theme.scale(screen)
                        color: previousButton.enabled ? Theme.accentPrimary : Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    }

                }

                // Play/Pause button
                Rectangle {
                    width: 36 * Theme.scale(screen)
                    height: 36 * Theme.scale(screen)
                    radius: width * 0.5
                    color: playButton.containsMouse ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.2) : Qt.darker(Theme.surface, 1.1)
                    border.color: Theme.accentPrimary
                    border.width: 2 * Theme.scale(screen)

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
                        font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
                        color: playButton.enabled ? Theme.accentPrimary : Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    }

                }

                // Next button
                Rectangle {
                    width: 28 * Theme.scale(screen)
                    height: 28 * Theme.scale(screen)
                    radius: width * 0.5
                    color: nextButton.containsMouse ? Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.2) : Qt.darker(Theme.surface, 1.1)
                    border.color: Qt.rgba(Theme.accentPrimary.r, Theme.accentPrimary.g, Theme.accentPrimary.b, 0.3)
                    border.width: 1 * Theme.scale(screen)

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
                        font.pixelSize: Theme.fontSizeCaption * Theme.scale(screen)
                        color: nextButton.enabled ? Theme.accentPrimary : Qt.rgba(Theme.textPrimary.r, Theme.textPrimary.g, Theme.textPrimary.b, 0.3)
                    }

                }

            }

        }

    }

}
