import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.Media
import qs.Services.UI
import qs.Widgets
import qs.Widgets.AudioSpectrum

SmartPanel {
  id: root

  preferredWidth: Math.round(400 * Style.uiScaleRatio)
  preferredHeight: Math.round((root.showAlbumArt ? 520 : 260) * Style.uiScaleRatio)

  readonly property var mediaMiniSettings: {
    try {
      var widgets = Settings.data.bar.widgets;
      var sections = ["left", "center", "right"];
      for (var i = 0; i < sections.length; i++) {
        var list = widgets[sections[i]];
        if (list) {
          for (var j = 0; j < list.length; j++) {
            if (list[j].id === "MediaMini") {
              return list[j];
            }
          }
        }
      }
    } catch (e) {}
    return {};
  }

  readonly property string visualizerType: (mediaMiniSettings && mediaMiniSettings.visualizerType !== undefined) ? mediaMiniSettings.visualizerType : "linear"
  readonly property bool showArtistFirst: !!(mediaMiniSettings && mediaMiniSettings.showArtistFirst !== undefined ? mediaMiniSettings.showArtistFirst : true)
  readonly property bool showAlbumArt: !!(mediaMiniSettings && mediaMiniSettings.showAlbumArt !== undefined ? mediaMiniSettings.showAlbumArt : true)
  readonly property bool showVisualizer: !!(mediaMiniSettings && mediaMiniSettings.showVisualizer !== undefined ? mediaMiniSettings.showVisualizer : true)

  readonly property bool needsCava: root.showVisualizer && root.visualizerType !== "" && root.visualizerType !== "none" && root.isPanelOpen

  onNeedsCavaChanged: {
    if (root.needsCava) {
      CavaService.registerComponent("mediaplayerpanel");
    } else {
      CavaService.unregisterComponent("mediaplayerpanel");
    }
  }

  Component.onCompleted: {
    if (root.needsCava) {
      CavaService.registerComponent("mediaplayerpanel");
    }
  }

  Component.onDestruction: {
    CavaService.unregisterComponent("mediaplayerpanel");
  }

  panelContent: Item {
    id: playerContent
    anchors.fill: parent

    Loader {
      id: visualizerLoaderCompact
      anchors.fill: parent
      anchors.margins: Style.marginL
      z: 0
      active: !!(root.needsCava && !root.showAlbumArt)
      sourceComponent: visualizerSource
    }

    property Component visualizerSource: {
      switch (root.visualizerType) {
      case "linear":
        return linearComponent;
      case "mirrored":
        return mirroredComponent;
      case "wave":
        return waveComponent;
      default:
        return null;
      }
    }

    // Main Column
    ColumnLayout {
      id: mainLayout
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginL
      z: 1

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NIcon {
          icon: "music"
          pointSize: Style.fontSizeL
          color: Color.mPrimary
        }

        NText {
          text: I18n.tr("common.media-player")
          font.weight: Style.fontWeightBold
          pointSize: Style.fontSizeL
          color: Color.mOnSurface
          Layout.fillWidth: true
        }

        Rectangle {
          radius: Style.radiusS
          color: playerSelectorMouse.containsMouse ? Color.mPrimary : "transparent"
          implicitWidth: playerRow.implicitWidth + Style.marginM
          implicitHeight: Style.baseWidgetSize * 0.8
          visible: MediaService.getAvailablePlayers().length > 1

          RowLayout {
            id: playerRow
            anchors.centerIn: parent
            spacing: Style.marginXS

            NText {
              text: MediaService.currentPlayer ? MediaService.currentPlayer.identity : "Select Player"
              pointSize: Style.fontSizeXS
              color: playerSelectorMouse.containsMouse ? Color.mOnPrimary : Color.mOnSurfaceVariant
            }
            NIcon {
              icon: "chevron-down"
              pointSize: Style.fontSizeXS
              color: playerSelectorMouse.containsMouse ? Color.mOnPrimary : Color.mOnSurfaceVariant
            }
          }

          MouseArea {
            id: playerSelectorMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: playerContextMenu.open()
          }

          Popup {
            id: playerContextMenu
            x: 0
            y: parent.height
            width: 160
            padding: Style.marginS

            background: Rectangle {
              color: Color.mSurfaceVariant
              border.color: Color.mOutline
              border.width: Style.borderS
              radius: Style.iRadiusM
            }

            contentItem: ColumnLayout {
              spacing: 0
              Repeater {
                model: MediaService.getAvailablePlayers()
                delegate: Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 30
                  color: "transparent"

                  Rectangle {
                    anchors.fill: parent
                    color: itemMouse.containsMouse ? Color.mPrimary : "transparent"
                    radius: Style.iRadiusS
                  }

                  RowLayout {
                    anchors.fill: parent
                    anchors.margins: Style.marginS
                    spacing: Style.marginS

                    NIcon {
                      visible: MediaService.currentPlayer && MediaService.currentPlayer.identity === modelData.identity
                      icon: "check"
                      color: itemMouse.containsMouse ? Color.mOnPrimary : Color.mPrimary
                      pointSize: Style.fontSizeS
                    }

                    NText {
                      text: modelData.identity
                      pointSize: Style.fontSizeS
                      color: itemMouse.containsMouse ? Color.mOnPrimary : Color.mOnSurface
                      Layout.fillWidth: true
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      MediaService.currentPlayer = modelData;
                      playerContextMenu.close();
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Album Art
      Item {
        id: albumArtItem
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 200
        visible: root.showAlbumArt

        Item {
          anchors.fill: parent
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: ShaderEffectSource {
              sourceItem: maskRect
              hideSource: true
            }
          }

          Rectangle {
            id: maskRect
            anchors.fill: parent
            radius: Style.radiusL
            color: "white"
            visible: false
          }

          Rectangle {
            anchors.fill: parent
            color: Color.mSurfaceVariant
          }

          Image {
            id: albumArt
            anchors.fill: parent
            source: MediaService.trackArtUrl
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: root.showAlbumArt && source != ""
          }

          // Fallback Icon
          NIcon {
            anchors.centerIn: parent
            icon: "disc"
            pointSize: Style.fontSizeXXXL * 2
            color: Color.mOnSurfaceVariant
            visible: root.showAlbumArt && albumArt.status !== Image.Ready
          }

          Loader {
            anchors.fill: parent
            anchors.margins: Style.marginS
            z: 2
            active: !!(root.needsCava && root.showAlbumArt)
            sourceComponent: visualizerSource
          }
        }
      }

      Component {
        id: linearComponent
        NLinearSpectrum {
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: 0.8
          anchors.bottom: parent.bottom
          height: parent.height * 0.4
          width: parent.width
        }
      }

      Component {
        id: mirroredComponent
        NMirroredSpectrum {
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: 0.8
          anchors.centerIn: parent
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width
        }
      }

      Component {
        id: waveComponent
        NWaveSpectrum {
          values: CavaService.values
          fillColor: Color.mPrimary
          opacity: 0.8
          anchors.centerIn: parent
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width
        }
      }

      ColumnLayout {
        id: controlsLayout
        Layout.fillWidth: true
        spacing: Style.marginS

        // Track Info
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0

          NText {
            text: {
              if (root.showArtistFirst) {
                return MediaService.trackArtist || (MediaService.trackAlbum || "Unknown Artist");
              } else {
                return MediaService.trackTitle || "No Media";
              }
            }

            pointSize: Style.fontSizeXL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            maximumLineCount: 2
          }

          NText {
            text: {
              if (root.showArtistFirst) {
                return MediaService.trackTitle || "No Media";
              } else {
                return MediaService.trackArtist || (MediaService.trackAlbum || "Unknown Artist");
              }
            }
            pointSize: Style.fontSizeM
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        // Progress Bar
        Item {
          id: progressWrapper
          visible: (MediaService.currentPlayer && MediaService.trackLength > 0)
          Layout.fillWidth: true
          height: Style.baseWidgetSize * 0.5

          property real localSeekRatio: -1
          property real lastSentSeekRatio: -1
          property real seekEpsilon: 0.01
          property real progressRatio: {
            if (!MediaService.currentPlayer || MediaService.trackLength <= 0)
              return 0;
            const r = MediaService.currentPosition / MediaService.trackLength;
            if (isNaN(r) || !isFinite(r))
              return 0;
            return Math.max(0, Math.min(1, r));
          }

          Timer {
            id: seekDebounce
            interval: 75
            repeat: false
            onTriggered: {
              if (MediaService.isSeeking && progressWrapper.localSeekRatio >= 0) {
                const next = Math.max(0, Math.min(1, progressWrapper.localSeekRatio));
                if (progressWrapper.lastSentSeekRatio < 0 || Math.abs(next - progressWrapper.lastSentSeekRatio) >= progressWrapper.seekEpsilon) {
                  MediaService.seekByRatio(next);
                  progressWrapper.lastSentSeekRatio = next;
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
            heightRatio: 0.4

            value: (!MediaService.isSeeking) ? progressWrapper.progressRatio : (progressWrapper.localSeekRatio >= 0 ? progressWrapper.localSeekRatio : 0)

            onMoved: {
              progressWrapper.localSeekRatio = value;
              seekDebounce.restart();
            }
            onPressedChanged: {
              if (pressed) {
                MediaService.isSeeking = true;
                progressWrapper.localSeekRatio = value;
                MediaService.seekByRatio(value);
                progressWrapper.lastSentSeekRatio = value;
              } else {
                seekDebounce.stop();
                MediaService.seekByRatio(value);
                MediaService.isSeeking = false;
                progressWrapper.localSeekRatio = -1;
                progressWrapper.lastSentSeekRatio = -1;
              }
            }
          }

          NText {
            anchors.left: parent.left
            anchors.top: parent.bottom
            text: MediaService.positionString || "0:00"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            visible: parent.visible
          }
          NText {
            anchors.right: parent.right
            anchors.top: parent.bottom
            text: MediaService.lengthString || "0:00"
            pointSize: Style.fontSizeXS
            color: Color.mOnSurfaceVariant
            visible: parent.visible
          }
        }

        Item {
          Layout.preferredHeight: Style.marginS
        }

        RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Style.marginXL

          NIconButton {
            icon: "media-prev"
            baseSize: Style.baseWidgetSize * 1.2
            onClicked: MediaService.previous()
          }

          // Play/Pause
          Rectangle {
            implicitWidth: Style.baseWidgetSize * 1.8
            implicitHeight: Style.baseWidgetSize * 1.8
            radius: Style.radiusL
            color: Color.mPrimary

            NIcon {
              anchors.centerIn: parent
              icon: MediaService.isPlaying ? "media-pause" : "media-play"
              pointSize: Style.fontSizeXXL
              color: Color.mOnPrimary
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onEntered: parent.color = Color.mPrimary
              onClicked: MediaService.playPause()
            }
          }

          NIconButton {
            icon: "media-next"
            baseSize: Style.baseWidgetSize * 1.2
            onClicked: MediaService.next()
          }
        }
      }
    }
  }
}
