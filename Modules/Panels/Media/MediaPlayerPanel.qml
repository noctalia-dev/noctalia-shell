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

  preferredWidth: Math.round((root.isSideBySide ? 480 : 400) * Style.uiScaleRatio)
  preferredHeight: Math.round((root.compactMode ? 240 : (root.showAlbumArt ? 560 : 300)) * Style.uiScaleRatio)

  property var mediaMiniSettings: {
    const widget = BarService.lookupWidget("MediaMini", screen?.name);
    return widget ? widget.widgetSettings : null;
  }

  function refreshMediaMiniSettings() {
    const widget = BarService.lookupWidget("MediaMini", screen?.name);
    root.mediaMiniSettings = widget ? widget.widgetSettings : null;
  }

  Connections {
    target: BarService
    function onActiveWidgetsChanged() {
      root.refreshMediaMiniSettings();
    }
  }

  Connections {
    target: Settings
    function onSettingsSaved() {
      root.refreshMediaMiniSettings();
    }
  }

  readonly property string visualizerType: (mediaMiniSettings && mediaMiniSettings.visualizerType !== undefined) ? mediaMiniSettings.visualizerType : "linear"
  readonly property bool showArtistFirst: !!(mediaMiniSettings && mediaMiniSettings.showArtistFirst !== undefined ? mediaMiniSettings.showArtistFirst : true)
  readonly property bool showAlbumArt: !!(mediaMiniSettings && mediaMiniSettings.panelShowAlbumArt !== undefined ? mediaMiniSettings.panelShowAlbumArt : true)
  readonly property bool showVisualizer: !!(mediaMiniSettings && mediaMiniSettings.showVisualizer !== undefined ? mediaMiniSettings.showVisualizer : true)
  readonly property bool compactMode: !!(mediaMiniSettings && mediaMiniSettings.compactMode !== undefined ? mediaMiniSettings.compactMode : false)
  readonly property string scrollingMode: (mediaMiniSettings && mediaMiniSettings.scrollingMode !== undefined) ? mediaMiniSettings.scrollingMode : "hover"

  readonly property bool isSideBySide: root.compactMode && root.showAlbumArt

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

    readonly property real contentPreferredHeight: (root.compactMode ? 240 : (root.showAlbumArt ? 560 : 300)) * Style.uiScaleRatio

    // Old loader removed from here

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

    // Layout
    ColumnLayout {
      id: mainLayout
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginL
      z: 1

      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: headerRow.implicitHeight + Style.margin2M

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

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

            NPopup {
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

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: root.close()
          }
        }
      }

      // Adaptive Content Area
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Visualizer background for content area
        Loader {
          anchors.fill: parent
          z: 0
          active: !!(root.needsCava && !root.showAlbumArt)
          sourceComponent: visualizerSource
        }

        GridLayout {
          anchors.fill: parent
          anchors.leftMargin: root.compactMode ? Style.marginL : Style.marginM
          anchors.rightMargin: root.compactMode ? Style.marginL : Style.marginM
          anchors.topMargin: Style.marginM
          anchors.bottomMargin: Style.marginM
          columns: root.isSideBySide ? 2 : 1
          columnSpacing: Style.marginL
          rowSpacing: Style.marginL

          // Album Art (Vertical in normal, Horizontal in compact)
          Item {
            id: albumArtItem
            Layout.preferredWidth: root.compactMode ? Math.round(110 * Style.uiScaleRatio) : parent.width
            Layout.preferredHeight: root.compactMode ? Math.round(110 * Style.uiScaleRatio) : (root.showAlbumArt ? -1 : 0)
            Layout.fillWidth: !root.compactMode
            Layout.fillHeight: !root.compactMode && root.showAlbumArt
            Layout.alignment: Qt.AlignVCenter
            visible: root.showAlbumArt

            NImageRounded {
              anchors.fill: parent
              radius: root.compactMode ? Style.radiusM : Style.radiusL
              imagePath: MediaService.trackArtUrl
              imageFillMode: Image.PreserveAspectCrop
              fallbackIcon: "disc"
              fallbackIconSize: root.compactMode ? Style.fontSizeXXXL * 3 : Style.fontSizeXXXL * 6
              borderWidth: 0
            }

            Loader {
              anchors.fill: parent
              anchors.margins: Style.marginS
              z: 2
              active: !!(root.needsCava && root.showAlbumArt)
              sourceComponent: visualizerSource
            }
          }

          ColumnLayout {
            id: controlsLayout
            Layout.fillWidth: true
            Layout.fillHeight: root.compactMode
            spacing: root.compactMode ? Style.marginXS : Style.marginS

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0

              NScrollText {
                Layout.fillWidth: true
                maxWidth: parent.width
                text: {
                  if (root.showArtistFirst) {
                    return MediaService.trackArtist || (MediaService.trackAlbum || "Unknown Artist");
                  } else {
                    return MediaService.trackTitle || "No Media";
                  }
                }

                scrollMode: {
                  if (root.scrollingMode === "always")
                    return NScrollText.ScrollMode.Always;
                  if (root.scrollingMode === "hover")
                    return NScrollText.ScrollMode.Hover;
                  return NScrollText.ScrollMode.Never;
                }
                gradientColor: Color.mSurfaceVariant
                cornerRadius: Style.radiusM

                delegate: NText {
                  pointSize: root.compactMode ? Style.fontSizeL : Style.fontSizeXL
                  font.weight: Style.fontWeightBold
                  color: Color.mOnSurface
                  horizontalAlignment: root.isSideBySide ? Text.AlignLeft : Text.AlignHCenter
                  elide: Text.ElideNone
                  wrapMode: Text.NoWrap
                }
              }

              NScrollText {
                Layout.fillWidth: true
                maxWidth: parent.width
                text: {
                  if (root.showArtistFirst) {
                    return MediaService.trackTitle || "No Media";
                  } else {
                    return MediaService.trackArtist || (MediaService.trackAlbum || "Unknown Artist");
                  }
                }

                scrollMode: {
                  if (root.scrollingMode === "always")
                    return NScrollText.ScrollMode.Always;
                  if (root.scrollingMode === "hover")
                    return NScrollText.ScrollMode.Hover;
                  return NScrollText.ScrollMode.Never;
                }
                gradientColor: Color.mSurfaceVariant
                cornerRadius: Style.radiusM

                delegate: NText {
                  pointSize: root.compactMode ? Style.fontSizeS : Style.fontSizeM
                  color: Color.mOnSurfaceVariant
                  horizontalAlignment: root.isSideBySide ? Text.AlignLeft : Text.AlignHCenter
                  elide: Text.ElideNone
                  wrapMode: Text.NoWrap
                }
              }
            }

            Item {
              id: progressWrapper
              visible: (MediaService.currentPlayer && MediaService.trackLength > 0)
              Layout.fillWidth: true
              Layout.preferredHeight: root.compactMode ? (Style.baseWidgetSize * 0.4) : (Style.baseWidgetSize * 0.5)

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
                anchors.topMargin: 2 // Small gap for side-by-side mode
                text: MediaService.positionString || "0:00"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                visible: parent.visible
              }
              NText {
                anchors.right: parent.right
                anchors.top: parent.bottom
                anchors.topMargin: 2
                text: MediaService.lengthString || "0:00"
                pointSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                visible: parent.visible
              }
            }

            Item {
              Layout.preferredHeight: root.isSideBySide ? Style.marginM : Style.marginS
            }

            RowLayout {
              Layout.alignment: Qt.AlignHCenter
              spacing: root.isSideBySide ? Style.marginL : Style.marginXL

              NIconButton {
                icon: "media-prev"
                baseSize: root.compactMode ? (Style.baseWidgetSize * 0.9) : (Style.baseWidgetSize * 1.2)
                onClicked: MediaService.previous()
              }

              Rectangle {
                implicitWidth: root.compactMode ? (Style.baseWidgetSize * 1.3) : (Style.baseWidgetSize * 1.8)
                implicitHeight: root.compactMode ? (Style.baseWidgetSize * 1.3) : (Style.baseWidgetSize * 1.8)
                radius: root.compactMode ? Style.iRadiusM : Style.iRadiusL
                color: Color.mPrimary

                NIcon {
                  anchors.centerIn: parent
                  icon: MediaService.isPlaying ? "media-pause" : "media-play"
                  pointSize: root.compactMode ? Style.fontSizeL : Style.fontSizeXXL
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
                baseSize: root.compactMode ? (Style.baseWidgetSize * 0.9) : (Style.baseWidgetSize * 1.2)
                onClicked: MediaService.next()
              }
            }
          }
        }
      }
    }
  }

  // Visualizer Components
  Component {
    id: linearComponent
    NLinearSpectrum {
      width: parent.width - Style.marginS
      height: 20
      values: CavaService.values
      fillColor: Color.mPrimary
      opacity: 0.4
      barPosition: Settings.getBarPositionForScreen(root.screen?.name)
    }
  }

  Component {
    id: mirroredComponent
    NMirroredSpectrum {
      width: parent.width - Style.marginS
      height: parent.height - Style.marginS
      values: CavaService.values
      fillColor: Color.mPrimary
      opacity: 0.4
    }
  }

  Component {
    id: waveComponent
    NWaveSpectrum {
      width: parent.width - Style.marginS
      height: parent.height - Style.marginS
      values: CavaService.values
      fillColor: Color.mPrimary
      opacity: 0.4
    }
  }
}
