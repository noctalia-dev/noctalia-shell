import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.Media
import qs.Services.UI
import qs.Widgets
import qs.Widgets.AudioSpectrum

DraggableDesktopWidget {
  id: root

  defaultY: 200

  // Widget settings
  readonly property string hideMode: (widgetData.hideMode !== undefined) ? widgetData.hideMode : "visible"
  readonly property bool showButtons: (widgetData.showButtons !== undefined) ? widgetData.showButtons : true
  readonly property bool hasPlayer: MediaService.currentPlayer !== null
  readonly property bool isPlaying: MediaService.isPlaying
  readonly property bool hasActiveTrack: hasPlayer && (MediaService.trackTitle || MediaService.trackArtist)

  // State
  // Hide when idle only if not playing AND no active track (to handle players like mpv that may not report playback state correctly)
  readonly property bool shouldHideIdle: (hideMode === "idle") && !isPlaying && !hasActiveTrack
  readonly property bool shouldHideEmpty: !hasPlayer && hideMode === "hidden"
  readonly property bool isHidden: (shouldHideIdle || shouldHideEmpty) && !DesktopWidgetRegistry.editMode
  visible: !isHidden

  // CavaService registration for visualizer
  readonly property string cavaComponentId: "desktopmediaplayer:" + (root.screen ? root.screen.name : "unknown")

  onShouldShowVisualizerChanged: {
    if (root.shouldShowVisualizer) {
      CavaService.registerComponent(root.cavaComponentId);
    } else {
      CavaService.unregisterComponent(root.cavaComponentId);
    }
  }

  Component.onCompleted: {
    if (root.shouldShowVisualizer) {
      CavaService.registerComponent(root.cavaComponentId);
    }
  }

  Component.onDestruction: {
    CavaService.unregisterComponent(root.cavaComponentId);
  }

  readonly property bool showPrev: hasPlayer && MediaService.canGoPrevious
  readonly property bool showNext: hasPlayer && MediaService.canGoNext
  readonly property int visibleButtonCount: root.showButtons ? (1 + (showPrev ? 1 : 0) + (showNext ? 1 : 0)) : 0
  readonly property int baseWidth: 400 * Style.uiScaleRatio
  readonly property int buttonWidth: 32 * Style.uiScaleRatio
  readonly property int buttonSpacing: Style.marginXS
  readonly property int controlsWidth: visibleButtonCount * buttonWidth + (visibleButtonCount > 1 ? (visibleButtonCount - 1) * buttonSpacing : 0)

  implicitWidth: baseWidth - (3 - visibleButtonCount) * (buttonWidth + buttonSpacing)
  implicitHeight: contentLayout.implicitHeight + Style.marginM * 2
  width: implicitWidth
  height: implicitHeight

  // Background container with masking (only visible when showBackground is true)
  Item {
    anchors.fill: parent
    anchors.margins: Style.marginXS
    z: 0
    clip: true
    visible: root.showBackground
    layer.enabled: true
    layer.smooth: true
    layer.samples: 4
    layer.effect: MultiEffect {
      maskEnabled: true
      maskThresholdMin: 0.95
      maskSpreadAtMin: 0.0
      maskSource: ShaderEffectSource {
        sourceItem: Rectangle {
          width: root.width - Style.marginXS * 2
          height: root.height - Style.marginXS * 2
          radius: Math.max(0, Style.radiusL - Style.marginXS)
          color: "white"
          antialiasing: true
          smooth: true
        }
        smooth: true
        mipmap: true
      }
    }
  }

  // Visualizer visibility mode
  readonly property string visualizerVisibility: (widgetData && widgetData.visualizerVisibility !== undefined) ? widgetData.visualizerVisibility : "always"
  readonly property bool shouldShowVisualizer: {
    if (!(widgetData && widgetData.visualizerType) || widgetData.visualizerType === "" || widgetData.visualizerType === "none")
      return false;
    if (visualizerVisibility === "always")
      return true;
    if (visualizerVisibility === "with-background")
      return root.showBackground;
    return true; // default to always visible
  }

  // Visualizer overlay (visibility controlled by visualizerVisibility setting)
  Loader {
    anchors.fill: parent
    anchors.margins: Style.marginXS
    z: 0
    clip: true
    active: shouldShowVisualizer
    layer.enabled: true
    layer.smooth: true
    layer.samples: 4
    layer.effect: MultiEffect {
      maskEnabled: true
      maskThresholdMin: 0.95
      maskSpreadAtMin: 0.0
      maskSource: ShaderEffectSource {
        sourceItem: Rectangle {
          width: root.width - Style.marginXS * 2
          height: root.height - Style.marginXS * 2
          radius: Math.max(0, Style.radiusL - Style.marginXS)
          color: "white"
          antialiasing: true
          smooth: true
        }
        smooth: true
        mipmap: true
      }
    }

    sourceComponent: {
      var visualizerType = (widgetData && widgetData.visualizerType) ? widgetData.visualizerType : "";
      switch (visualizerType) {
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

    Component {
      id: linearComponent
      NLinearSpectrum {
        anchors.fill: parent
        values: CavaService.values
        fillColor: Color.mPrimary
        opacity: 0.6
      }
    }

    Component {
      id: mirroredComponent
      NMirroredSpectrum {
        anchors.fill: parent
        values: CavaService.values
        fillColor: Color.mPrimary
        opacity: 0.6
      }
    }

    Component {
      id: waveComponent
      NWaveSpectrum {
        anchors.fill: parent
        values: CavaService.values
        fillColor: Color.mPrimary
        opacity: 0.6
      }
    }
  }

  RowLayout {
    id: contentLayout
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: Style.marginS
    z: 2

    Item {
      Layout.preferredWidth: 64 * Style.uiScaleRatio
      Layout.preferredHeight: 64 * Style.uiScaleRatio
      Layout.alignment: Qt.AlignVCenter

      NImageRounded {
        visible: hasPlayer
        anchors.fill: parent
        radius: width / 2
        imagePath: MediaService.trackArtUrl
        fallbackIcon: isPlaying ? "media-pause" : "media-play"
        fallbackIconSize: 20 * Style.uiScaleRatio
        borderWidth: 0
      }

      NIcon {
        visible: !hasPlayer
        anchors.centerIn: parent
        icon: "disc"
        pointSize: 24
        color: Color.mOnSurfaceVariant
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      NText {
        Layout.fillWidth: true
        text: hasPlayer ? (MediaService.trackTitle || "Unknown Track") : "No media playing"
        pointSize: Style.fontSizeS
        font.weight: Style.fontWeightSemiBold
        color: Color.mOnSurface
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      NText {
        visible: hasPlayer && MediaService.trackArtist
        Layout.fillWidth: true
        text: MediaService.trackArtist || ""
        pointSize: Style.fontSizeXS
        font.weight: Style.fontWeightRegular
        color: Color.mOnSurfaceVariant
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }

    RowLayout {
      id: controlsRow
      spacing: Style.marginXS
      z: 10
      visible: root.showButtons

      NIconButton {
        visible: showPrev
        baseSize: 32
        icon: "media-prev"
        enabled: hasPlayer && MediaService.canGoPrevious
        colorBg: Color.mSurfaceVariant
        colorFg: enabled ? Color.mPrimary : Color.mOnSurfaceVariant
        onClicked: {
          if (enabled)
            MediaService.previous();
        }
      }

      NIconButton {
        baseSize: 36
        icon: isPlaying ? "media-pause" : "media-play"
        enabled: hasPlayer && (MediaService.canPlay || MediaService.canPause)
        colorBg: Color.mPrimary
        colorFg: Color.mOnPrimary
        colorBgHover: Qt.lighter(Color.mPrimary, 1.1)
        colorFgHover: Color.mOnPrimary
        onClicked: {
          if (enabled) {
            MediaService.playPause();
          }
        }
      }

      NIconButton {
        visible: showNext
        baseSize: 32
        icon: "media-next"
        enabled: hasPlayer && MediaService.canGoNext
        colorBg: Color.mSurfaceVariant
        colorFg: enabled ? Color.mPrimary : Color.mOnSurfaceVariant
        onClicked: {
          if (enabled)
            MediaService.next();
        }
      }
    }
  }
}
