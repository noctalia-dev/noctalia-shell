import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Modules.Audio
import qs.Commons
import qs.Services
import qs.Widgets

// Media player area (placeholder until MediaPlayer service is wired)
NBox {
  id: root

  Layout.fillWidth: true
  Layout.fillHeight: true

  // Let content dictate the height (no hardcoded height here)
  // Height can be overridden by parent layout (SidePanel binds it to stats card)
  //implicitHeight: content.implicitHeight + Style.marginLarge * 2 * scaling
  // Component.onCompleted: {
  //   Logger.logMediaService.trackArtUrl)
  // }
  ColumnLayout {
    anchors.fill: parent
    Layout.fillHeight: true
    anchors.margins: Style.marginLarge * scaling

    // Fallback
    ColumnLayout {
      id: fallback

      visible: !main.visible
      spacing: Style.marginSmall * scaling

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
      }

      NIcon {
        text: "album"
        font.pointSize: Style.fontSizeXXL * 2.5 * scaling
        color: Color.mPrimary
        Layout.alignment: Qt.AlignHCenter
      }
      NText {
        text: "No media player detected"
        color: Color.mOnSurfaceVariant
        Layout.alignment: Qt.AlignHCenter
      }

      Item {
        Layout.fillWidth: true
      }
    }

    // MediaPlayer Main Content
    ColumnLayout {
      id: main

      visible: MediaService.currentPlayer && MediaService.canPlay
      spacing: Style.marginMedium * scaling

      // Player selector
      ComboBox {
        id: playerSelector
        Layout.fillWidth: true
        Layout.preferredHeight: Style.barHeight * 0.83 * scaling
        visible: MediaService.getAvailablePlayers().length > 1
        model: MediaService.getAvailablePlayers()
        textRole: "identity"
        currentIndex: MediaService.selectedPlayerIndex

        background: Rectangle {
          visible: false
          // implicitWidth: 120 * scaling
          // implicitHeight: 30 * scaling
          color: Color.transparent
          border.color: playerSelector.activeFocus ? Color.mTertiary : Color.mOutline
          border.width: Math.max(1, Style.borderThin * scaling)
          radius: Style.radiusMedium * scaling
        }

        contentItem: NText {
          visible: false
          leftPadding: Style.marginMedium * scaling
          rightPadding: playerSelector.indicator.width + playerSelector.spacing
          text: playerSelector.displayText
          font.pointSize: Style.fontSizeSmall * scaling
          color: Color.mOnSurface
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        indicator: NIcon {
          x: playerSelector.width - width
          y: playerSelector.topPadding + (playerSelector.availableHeight - height) / 2
          text: "arrow_drop_down"
          font.pointSize: Style.fontSizeXL * scaling
          color: Color.mOnSurface
          horizontalAlignment: Text.AlignRight
        }

        popup: Popup {
          id: popup
          x: playerSelector.width * 0.5
          y: playerSelector.height * 0.75
          width: playerSelector.width * 0.5
          implicitHeight: Math.min(160 * scaling, contentItem.implicitHeight + Style.marginMedium * scaling)
          padding: Style.marginSmall * scaling

          contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: playerSelector.popup.visible ? playerSelector.delegateModel : null
            currentIndex: playerSelector.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
          }

          background: Rectangle {
            color: Color.mSurface
            border.color: Color.mOutline
            border.width: Math.max(1, Style.borderThin * scaling)
            radius: Style.radiusTiny * scaling
          }
        }

        delegate: ItemDelegate {
          width: playerSelector.width
          contentItem: NText {
            text: modelData.identity
            font.pointSize: Style.fontSizeSmall * scaling
            color: highlighted ? Color.mSurface : Color.mOnSurface
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
          }
          highlighted: playerSelector.highlightedIndex === index

          background: Rectangle {
            width: popup.width - Style.marginSmall * scaling * 2
            color: highlighted ? Color.mTertiary : Color.transparent
            radius: Style.radiusTiny * scaling
          }
        }

        onActivated: {
          MediaService.selectedPlayerIndex = currentIndex
          MediaService.updateCurrentPlayer()
        }
      }

      RowLayout {
        spacing: Style.marginMedium * scaling

        // -------------------------
        // Rounded thumbnail image
        Rectangle {

          width: 90 * scaling
          height: 90 * scaling
          radius: width * 0.5
          color: trackArt.visible ? Color.mPrimary : Color.transparent
          border.color: trackArt.visible ? Color.mOutline : Color.transparent
          border.width: Math.max(1, Style.borderThin * scaling)
          clip: true

          NImageRounded {
            id: trackArt
            visible: MediaService.trackArtUrl.toString() !== ""

            anchors.fill: parent
            anchors.margins: Style.marginTiny * scaling
            imagePath: MediaService.trackArtUrl
            fallbackIcon: "music_note"
            borderColor: Color.mOutline
            borderWidth: Math.max(1, Style.borderThin * scaling)
            imageRadius: width * 0.5
          }

          // Fallback icon when no album art available
          NIcon {
            text: "album"
            color: Color.mPrimary
            font.pointSize: Style.fontSizeLarge * 12 * scaling
            visible: !trackArt.visible
            anchors.centerIn: parent
          }
        }

        // -------------------------
        // Track metadata
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.marginTiny * scaling

          NText {
            visible: MediaService.trackTitle !== ""
            text: MediaService.trackTitle
            font.pointSize: Style.fontSizeMedium * scaling
            font.weight: Style.fontWeightBold
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            maximumLineCount: 2
            Layout.fillWidth: true
          }

          NText {
            visible: MediaService.trackArtist !== ""
            text: MediaService.trackArtist
            color: Color.mOnSurface
            font.pointSize: Style.fontSizeSmall * scaling
            elide: Text.ElideRight
            Layout.fillWidth: true
          }

          NText {
            visible: MediaService.trackAlbum !== ""
            text: MediaService.trackAlbum
            color: Color.mOnSurface
            font.pointSize: Style.fontSizeSmall * scaling
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }
      }

      // -------------------------
      // Progress bar
      Rectangle {
        id: progressBarBackground
        visible: (MediaService.currentPlayer && MediaService.trackLength > 0)
        width: parent.width
        height: 4 * scaling
        radius: Style.radiusSmall * scaling
        color: Color.mSurface
        Layout.fillWidth: true

        property real progressRatio: {
          if (!MediaService.currentPlayer || !MediaService.isPlaying || MediaService.trackLength <= 0) {
            return 0
          }
          return Math.min(1, MediaService.currentPosition / MediaService.trackLength)
        }

        Rectangle {
          id: progressFill
          width: progressBarBackground.progressRatio * parent.width
          height: parent.height
          radius: parent.radius
          color: Color.mPrimary

          Behavior on width {
            NumberAnimation {
              duration: Style.animationFast
            }
          }
        }

        // Interactive progress handle
        Rectangle {
          id: progressHandle
          visible: (MediaService.currentPlayer && MediaService.trackLength > 0)
          width: 16 * scaling
          height: 16 * scaling
          radius: width * 0.5
          color: Color.mPrimary
          border.color: Color.mOutline
          border.width: Math.max(1 * Style.borderMedium * scaling)
          x: Math.max(0, Math.min(parent.width - width, progressFill.width - width / 2))
          anchors.verticalCenter: parent.verticalCenter
          scale: progressMouseArea.containsMouse || progressMouseArea.pressed ? 1.2 : 1.0

          Behavior on scale {
            NumberAnimation {
              duration: Style.animationFast
            }
          }
        }

        // Mouse area for seeking
        MouseArea {
          id: progressMouseArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          enabled: MediaService.trackLength > 0 && MediaService.canSeek

          onClicked: function (mouse) {
            let ratio = mouse.x / width
            MediaService.seekByRatio(ratio)
          }

          onPositionChanged: function (mouse) {
            if (pressed) {
              let ratio = Math.max(0, Math.min(1, mouse.x / width))
              MediaService.seekByRatio(ratio)
            }
          }
        }
      }

      // -------------------------
      // Media controls
      RowLayout {
        spacing: Style.marginMedium * scaling
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter

        // Previous button
        NIconButton {
          icon: "skip_previous"
          tooltipText: "Previous Media"
          visible: MediaService.canGoPrevious
          onClicked: MediaService.canGoPrevious ? MediaService.previous() : {}
        }

        // Play/Pause button
        NIconButton {
          icon: MediaService.isPlaying ? "pause" : "play_arrow"
          tooltipText: MediaService.isPlaying ? "Pause" : "Play"
          visible: (MediaService.canPlay || MediaService.canPause)
          onClicked: (MediaService.canPlay || MediaService.canPause) ? MediaService.playPause() : {}
        }

        // Next button
        NIconButton {
          icon: "skip_next"
          tooltipText: "Next Media"
          visible: MediaService.canGoNext
          onClicked: MediaService.canGoNext ? MediaService.next() : {}
        }
      }
    }

    Loader {
      active: Settings.data.audio.visualizerType == "linear"
      Layout.alignment: Qt.AlignHCenter

      sourceComponent: LinearSpectrum {
        width: 300 * scaling
        height: 80 * scaling
        values: CavaService.values
        fillColor: Color.mPrimary
        Layout.alignment: Qt.AlignHCenter
      }
    }

    Loader {
      active: Settings.data.audio.visualizerType == "wave"
      Layout.alignment: Qt.AlignHCenter

      sourceComponent: WaveSpectrum {
        width: 300 * scaling
        height: 80 * scaling
        values: CavaService.values
        fillColor: Color.mPrimary
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }
}
