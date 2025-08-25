import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.Audio
import qs.Commons
import qs.Services
import qs.Widgets

Row {
  id: root

  property ShellScreen screen
  property real scaling: ScalingService.scale(screen)

  anchors.verticalCenter: parent.verticalCenter
  spacing: Style.marginS * scaling
  visible: MediaService.currentPlayer !== null && MediaService.canPlay
  width: MediaService.currentPlayer !== null && MediaService.canPlay ? implicitWidth : 0

  function getTitle() {
    return MediaService.trackTitle + (MediaService.trackArtist !== "" ? ` - ${MediaService.trackArtist}` : "")
  }

  //  A hidden text element to safely measure the full title width
  NText {
    id: fullTitleMetrics
    visible: false
    text: titleText.text
    font: titleText.font
  }

  Rectangle {
    // Let the Rectangle size itself based on its content (the Row)
    width: row.width + Style.marginM * scaling * 2

    height: Math.round(Style.capsuleHeight * scaling)
    radius: Math.round(Style.radiusM * scaling)
    color: Color.mSurfaceVariant

    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: mainContainer
      anchors.fill: parent
      anchors.leftMargin: Style.marginS * scaling
      anchors.rightMargin: Style.marginS * scaling

      Loader {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        active: Settings.data.audio.showMiniplayerCava && Settings.data.audio.visualizerType == "linear"
                && MediaService.isPlaying
        z: 0

        sourceComponent: LinearSpectrum {
          width: mainContainer.width - Style.marginS * scaling
          height: 20 * scaling
          values: CavaService.values
          fillColor: Color.mOnSurfaceVariant
          opacity: 0.4
        }

        Loader {
          anchors.verticalCenter: parent.verticalCenter
          anchors.horizontalCenter: parent.horizontalCenter
          active: Settings.data.audio.showMiniplayerCava && Settings.data.audio.visualizerType == "mirrored"
                  && MediaService.isPlaying
          z: 0

          sourceComponent: MirroredSpectrum {
            width: mainContainer.width - Style.marginS * scaling
            height: mainContainer.height - Style.marginS * scaling
            values: CavaService.values
            fillColor: Color.mOnSurfaceVariant
            opacity: 0.4
          }
        }

        Loader {
          anchors.verticalCenter: parent.verticalCenter
          anchors.horizontalCenter: parent.horizontalCenter
          active: Settings.data.audio.showMiniplayerCava && Settings.data.audio.visualizerType == "wave"
                  && MediaService.isPlaying
          z: 0

          sourceComponent: WaveSpectrum {
            width: mainContainer.width - Style.marginS * scaling
            height: mainContainer.height - Style.marginS * scaling
            values: CavaService.values
            fillColor: Color.mOnSurfaceVariant
            opacity: 0.4
          }
        }
      }

      Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginXS * scaling
        z: 1 // Above the visualizer

        NIcon {
          id: windowIcon
          text: MediaService.isPlaying ? "pause" : "play_arrow"
          font.pointSize: Style.fontSizeL * scaling
          verticalAlignment: Text.AlignVCenter
          anchors.verticalCenter: parent.verticalCenter
          visible: !Settings.data.audio.showMiniplayerAlbumArt && getTitle() !== "" && !trackArt.visible
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          visible: Settings.data.audio.showMiniplayerAlbumArt

          Rectangle {
            width: 18 * scaling
            height: 18 * scaling
            radius: width * 0.5
            color: Color.transparent
            antialiasing: true
            clip: true

            NImageCircled {
              id: trackArt
              visible: MediaService.trackArtUrl.toString() !== ""
              anchors.fill: parent
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: scaling
              imagePath: MediaService.trackArtUrl
              fallbackIcon: MediaService.isPlaying ? "pause" : "play_arrow"
              borderWidth: 0
              border.color: Color.transparent
            }

            // Fallback icon when no album art available
            NIcon {
              id: windowIconFallback
              text: MediaService.isPlaying ? "pause" : "play_arrow"
              font.pointSize: Style.fontSizeL * scaling
              verticalAlignment: Text.AlignVCenter
              anchors.verticalCenter: parent.verticalCenter
              visible: getTitle() !== "" && !trackArt.visible
            }
          }
        }

        NText {
          id: titleText

          // If hovered or just switched window, show up to 400 pixels
          // If not hovered show up to 150 pixels
          width: (mouseArea.containsMouse) ? Math.min(fullTitleMetrics.contentWidth,
                                                      400 * scaling) : Math.min(fullTitleMetrics.contentWidth,
                                                                                150 * scaling)
          text: getTitle()
          font.pointSize: Style.fontSizeS * scaling
          font.weight: Style.fontWeightMedium
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
          verticalAlignment: Text.AlignVCenter
          color: Color.mTertiary

          Behavior on width {
            NumberAnimation {
              duration: Style.animationSlow
              easing.type: Easing.InOutCubic
            }
          }
        }
      }

      // Mouse area for hover detection
      MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: MediaService.playPause()
      }
    }
  }
}
