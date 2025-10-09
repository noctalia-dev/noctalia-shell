import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import qs.Modules.Audio
import qs.Commons
import qs.Services
import qs.Widgets

NBox {
  id: root

  // Background artwork that covers everything
  Item {
    anchors.fill: parent
    clip: true

    NImageRounded {
      id: bgArtImage
      anchors.fill: parent
      imagePath: MediaService.trackArtUrl
      imageRadius: Style.radiusM * scaling
      visible: MediaService.trackArtUrl !== ""
    }

    // Dark overlay for readability
    Rectangle {
      anchors.fill: parent
      color: Color.mSurfaceVariant
      opacity: 0.85
      radius: Style.radiusM * scaling
    }

    // Border
    Rectangle {
      anchors.fill: parent
      color: Color.transparent
      border.color: Color.mOutline
      border.width: 1
      radius: Style.radiusM * scaling
    }
  }

  // Background visualizer on top of the artwork
  Item {
    id: visualizerContainer
    anchors.fill: parent
    layer.enabled: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskThresholdMin: 0.5
      maskSpreadAtMin: 0.0
      maskSource: ShaderEffectSource {
        sourceItem: Rectangle {
          width: root.width
          height: root.height
          radius: Style.radiusM * scaling
          color: "white"
        }
      }
    }

    Loader {
      anchors.fill: parent
      active: Settings.data.audio.visualizerType !== "" && Settings.data.audio.visualizerType !== "none"

      sourceComponent: {
        switch (Settings.data.audio.visualizerType) {
        case "linear":
          return linearComponent
        case "mirrored":
          return mirroredComponent
        case "wave":
          return waveComponent
        default:
          return null
        }
      }

      Component {
        id: linearComponent
        LinearSpectrum {
          anchors.fill: parent
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: MediaService.trackArtUrl !== "" ? 0.4 : 0.8
        }
      }

      Component {
        id: mirroredComponent
        MirroredSpectrum {
          anchors.fill: parent
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: MediaService.trackArtUrl !== "" ? 0.4 : 0.8
        }
      }

      Component {
        id: waveComponent
        WaveSpectrum {
          anchors.fill: parent
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: MediaService.trackArtUrl !== "" ? 0.4 : 0.8
        }
      }
    }
  }

  // Player selector - positioned at the very top
  Rectangle {
    id: playerSelectorButton
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: Style.marginXS * scaling
    anchors.leftMargin: Style.marginM * scaling
    anchors.rightMargin: Style.marginM * scaling
    height: Style.barHeight * scaling
    visible: MediaService.getAvailablePlayers().length > 1
    radius: Style.radiusM * scaling
    color: Color.transparent

    property var currentPlayer: MediaService.getAvailablePlayers()[MediaService.selectedPlayerIndex]

    RowLayout {
      anchors.fill: parent
      spacing: Style.marginS * scaling

      NIcon {
        icon: "caret-down"
        pointSize: Style.fontSizeXXL * scaling
        color: Color.mOnSurfaceVariant
      }

      NText {
        text: playerSelectorButton.currentPlayer ? playerSelectorButton.currentPlayer.identity : ""
        pointSize: Style.fontSizeXS * scaling
        color: Color.mOnSurfaceVariant
        Layout.fillWidth: true
      }
    }

    MouseArea {
      id: playerSelectorMouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onClicked: {
        var menuItems = []
        var players = MediaService.getAvailablePlayers()
        for (var i = 0; i < players.length; i++) {
          menuItems.push({
                           "label": players[i].identity,
                           "action": i.toString(),
                           "icon": "disc",
                           "enabled": true,
                           "visible": true
                         })
        }
        playerContextMenu.model = menuItems
        playerContextMenu.openAtItem(playerSelectorButton, playerSelectorButton.width - playerContextMenu.width, playerSelectorButton.height)
      }
    }

    NContextMenu {
      id: playerContextMenu
      parent: root
      width: 200 * scaling

      onTriggered: function (action) {
        var index = parseInt(action)
        if (!isNaN(index)) {
          MediaService.selectedPlayerIndex = index
          MediaService.updateCurrentPlayer()
        }
      }
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM * scaling

    // No media player detected
    ColumnLayout {
      id: fallback

      visible: !main.visible
      spacing: Style.marginS * scaling

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginL * scaling

          Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Style.fontSizeXXXL * 4 * scaling
            Layout.preferredHeight: Style.fontSizeXXXL * 4 * scaling

            // Pulsating audio circles (background)
            Repeater {
              model: 3
              Rectangle {
                anchors.centerIn: parent
                width: parent.width * (1.0 + index * 0.2)
                height: width
                radius: width / 2
                color: "transparent"
                border.color: Color.mOnSurfaceVariant
                border.width: 2
                opacity: 0

                SequentialAnimation on opacity {
                  running: true
                  loops: Animation.Infinite
                  PauseAnimation {
                    duration: index * 600
                  }
                  NumberAnimation {
                    from: 1.0
                    to: 0
                    duration: 2000
                    easing.type: Easing.OutQuad
                  }
                }

                SequentialAnimation on scale {
                  running: true
                  loops: Animation.Infinite
                  PauseAnimation {
                    duration: index * 600
                  }
                  NumberAnimation {
                    from: 0.5
                    to: 1.2
                    duration: 2000
                    easing.type: Easing.OutQuad
                  }
                }
              }
            }

            // Spinning disc
            NIcon {
              anchors.centerIn: parent
              icon: "disc"
              pointSize: Style.fontSizeXXXL * 3 * scaling
              color: Color.mOnSurfaceVariant

              RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 8000
                loops: Animation.Infinite
                running: true
              }
            }
          }

          // Descriptive text
          ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Style.marginXS * scaling
          }
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
      }
    }

    // MediaPlayer Main Content
    ColumnLayout {
      id: main

      visible: MediaService.currentPlayer && MediaService.canPlay
      spacing: Style.marginS * scaling

      // Spacer to push content down
      Item {
        Layout.preferredHeight: Style.marginM * scaling
      }

      // Metadata at the bottom left
      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignLeft
        spacing: Style.marginXS * scaling

        NText {
          visible: MediaService.trackTitle !== ""
          text: MediaService.trackTitle
          pointSize: Style.fontSizeM * scaling
          font.weight: Style.fontWeightBold
          elide: Text.ElideRight
          wrapMode: Text.Wrap
          maximumLineCount: 2
          Layout.fillWidth: true
        }

        NText {
          visible: MediaService.trackArtist !== ""
          text: MediaService.trackArtist
          color: Color.mPrimary
          pointSize: Style.fontSizeS * scaling
          elide: Text.ElideRight
          Layout.fillWidth: true
        }

        NText {
          visible: MediaService.trackAlbum !== ""
          text: MediaService.trackAlbum
          color: Color.mOnSurfaceVariant
          pointSize: Style.fontSizeM * scaling
          elide: Text.ElideRight
          Layout.fillWidth: true
        }
      }

      // Progress slider
      Item {
        id: progressWrapper
        visible: (MediaService.currentPlayer && MediaService.trackLength > 0)
        Layout.fillWidth: true
        height: Style.baseWidgetSize * 0.5 * scaling

        property real localSeekRatio: -1
        property real lastSentSeekRatio: -1
        property real seekEpsilon: 0.01
        property real progressRatio: {
          if (!MediaService.currentPlayer || MediaService.trackLength <= 0)
            return 0
          const r = MediaService.currentPosition / MediaService.trackLength
          if (isNaN(r) || !isFinite(r))
            return 0
          return Math.max(0, Math.min(1, r))
        }
        property real effectiveRatio: (MediaService.isSeeking && localSeekRatio >= 0) ? Math.max(0, Math.min(1, localSeekRatio)) : progressRatio

        Timer {
          id: seekDebounce
          interval: 75
          repeat: false
          onTriggered: {
            if (MediaService.isSeeking && progressWrapper.localSeekRatio >= 0) {
              const next = Math.max(0, Math.min(1, progressWrapper.localSeekRatio))
              if (progressWrapper.lastSentSeekRatio < 0 || Math.abs(next - progressWrapper.lastSentSeekRatio) >= progressWrapper.seekEpsilon) {
                MediaService.seekByRatio(next)
                progressWrapper.lastSentSeekRatio = next
              }
            }
          }
        }

        NSlider {
          id: progressSlider
          anchors.fill: parent
          from: 0
          to: 1
          stepSize: 0
          snapAlways: false
          enabled: MediaService.trackLength > 0 && MediaService.canSeek
          heightRatio: 0.65

          onMoved: {
            progressWrapper.localSeekRatio = value
            seekDebounce.restart()
          }
          onPressedChanged: {
            if (pressed) {
              MediaService.isSeeking = true
              progressWrapper.localSeekRatio = value
              MediaService.seekByRatio(value)
              progressWrapper.lastSentSeekRatio = value
            } else {
              seekDebounce.stop()
              MediaService.seekByRatio(value)
              MediaService.isSeeking = false
              progressWrapper.localSeekRatio = -1
              progressWrapper.lastSentSeekRatio = -1
            }
          }
        }

        Binding {
          target: progressSlider
          property: "value"
          value: progressWrapper.progressRatio
          when: !MediaService.isSeeking
        }
      }

      // Spacer to push media controls down
      Item {
        Layout.preferredHeight: Style.marginL * scaling
      }

      // Media controls
      RowLayout {
        spacing: Style.marginS * scaling
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter

        NIconButton {
          icon: "media-prev"
          visible: MediaService.canGoPrevious
          onClicked: MediaService.canGoPrevious ? MediaService.previous() : {}
        }

        NIconButton {
          icon: MediaService.isPlaying ? "media-pause" : "media-play"
          visible: (MediaService.canPlay || MediaService.canPause)
          onClicked: (MediaService.canPlay || MediaService.canPause) ? MediaService.playPause() : {}
        }

        NIconButton {
          icon: "media-next"
          visible: MediaService.canGoNext
          onClicked: MediaService.canGoNext ? MediaService.next() : {}
        }
      }
    }
  }
}
