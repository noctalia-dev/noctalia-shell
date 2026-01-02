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

  // Widget settings - check widgetData exists before accessing properties
  readonly property string hideMode: (widgetData && widgetData.hideMode !== undefined) ? widgetData.hideMode : "visible"
  readonly property bool showButtons: (widgetData && widgetData.showButtons !== undefined) ? widgetData.showButtons : true
  readonly property bool showAlbumArt: (widgetData && widgetData.showAlbumArt !== undefined) ? widgetData.showAlbumArt : true
  readonly property bool showVisualizer: (widgetData && widgetData.showVisualizer !== undefined) ? widgetData.showVisualizer : true
  readonly property string visualizerType: (widgetData && widgetData.visualizerType && widgetData.visualizerType !== "") ? widgetData.visualizerType : "linear"
  readonly property bool roundedCorners: (widgetData && widgetData.roundedCorners !== undefined) ? widgetData.roundedCorners : true
  readonly property bool hasPlayer: MediaService.currentPlayer !== null
  readonly property bool isPlaying: MediaService.isPlaying
  readonly property bool hasActiveTrack: hasPlayer && (MediaService.trackTitle || MediaService.trackArtist)

  // State
  // Hide when idle when playback is not active
  readonly property bool shouldHideIdle: (hideMode === "idle") && !isPlaying
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

  implicitWidth: Math.round(400 * widgetScale)
  implicitHeight: Math.round(64 * widgetScale + Style.marginM * widgetScale * 2)
  width: implicitWidth
  height: implicitHeight

  // Visualizer visibility mode
  readonly property bool shouldShowVisualizer: {
    if (!root.showVisualizer)
      return false;
    if (root.visualizerType === "" || root.visualizerType === "none")
      return false;
    return true;
  }

  // Visualizer overlay (visibility controlled by visualizerVisibility setting)
  // Completely disabled during scaling to avoid expensive canvas redraws
  Loader {
    anchors.fill: parent
    anchors.leftMargin: Math.round(Style.marginXS * widgetScale)
    anchors.rightMargin: Math.round(Style.marginXS * widgetScale)
    anchors.topMargin: Math.round(Style.marginXS * widgetScale)
    anchors.bottomMargin: 0
    z: 0
    clip: true
    active: shouldShowVisualizer
    layer.enabled: root.roundedCorners
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskThresholdMin: 0.95
      maskSpreadAtMin: 0.0
      maskSource: ShaderEffectSource {
        sourceItem: Rectangle {
          width: root.width - Math.round(Style.marginXS * widgetScale) * 2
          height: root.height - Math.round(Style.marginXS * widgetScale)
          radius: root.roundedCorners ? Math.round(Math.max(0, (Style.radiusL - Style.marginXS) * widgetScale)) : 0
          color: "white"
        }
      }
    }

    sourceComponent: {
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

    Component {
      id: linearComponent
      NLinearSpectrum {
        anchors.fill: parent
        values: CavaService.values
        fillColor: Color.mPrimary
        opacity: 1.0
      }
    }

    Component {
      id: mirroredComponent
      NMirroredSpectrum {
        anchors.fill: parent
        values: CavaService.values
        fillColor: Color.mPrimary
        opacity: 1.0
      }
    }

    Component {
      id: waveComponent
      NWaveSpectrum {
        anchors.fill: parent
        values: CavaService.values
        fillColor: Color.mPrimary
        opacity: 1.0
      }
    }
  }

  // Drop shadow for text and controls readability over visualizer
  // Disabled during scaling to avoid expensive recomputations
  NDropShadow {
    visible: !root.isScaling
    anchors.fill: contentLayout
    source: contentLayout
    z: 1
    autoPaddingEnabled: true
    shadowBlur: 1.0
    shadowOpacity: 0.9
    shadowHorizontalOffset: 0
    shadowVerticalOffset: 0
  }

  RowLayout {
    id: contentLayout
    states: [
      State {
        when: root.showButtons
        AnchorChanges {
          target: contentLayout
          anchors.horizontalCenter: undefined
          anchors.verticalCenter: undefined
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
        }
      },
      State {
        when: !root.showButtons
        AnchorChanges {
          target: contentLayout
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.verticalCenter: parent.verticalCenter
          anchors.top: undefined
          anchors.bottom: undefined
          anchors.left: undefined
          anchors.right: undefined
        }
      }
    ]
    anchors.margins: Math.round(Style.marginM * widgetScale)
    spacing: Math.round(Style.marginS * widgetScale)
    z: 2

    Item {
      visible: root.showAlbumArt
      Layout.preferredWidth: Math.round(48 * widgetScale)
      Layout.preferredHeight: Math.round(48 * widgetScale)
      Layout.alignment: Qt.AlignVCenter

      NImageRounded {
        visible: hasPlayer
        anchors.fill: parent
        radius: Math.round(Style.radiusM * widgetScale)
        imagePath: MediaService.trackArtUrl
        imageFillMode: Image.PreserveAspectCrop
        fallbackIcon: isPlaying ? "media-pause" : "media-play"
        fallbackIconSize: Math.round(20 * widgetScale)
        borderWidth: 0
      }

      NIcon {
        visible: !hasPlayer
        anchors.centerIn: parent
        icon: "disc"
        pointSize: Math.round(24 * widgetScale)
        color: Color.mOnSurfaceVariant
      }
    }

    ColumnLayout {
      visible: root.showAlbumArt
      Layout.fillWidth: true
      Layout.alignment: root.showButtons ? Qt.AlignVCenter : Qt.AlignCenter
      spacing: 0

      NText {
        Layout.fillWidth: true
        text: hasPlayer ? (MediaService.trackTitle || "Unknown Track") : "No media playing"
        pointSize: Math.round(Style.fontSizeS * widgetScale)
        font.weight: Style.fontWeightSemiBold
        color: Color.mOnSurface
        elide: Text.ElideRight
        maximumLineCount: 1
      }

      NText {
        visible: hasPlayer && MediaService.trackArtist
        Layout.fillWidth: true
        text: MediaService.trackArtist || ""
        pointSize: Math.round(Style.fontSizeXS * widgetScale)
        font.weight: Style.fontWeightRegular
        color: Color.mSecondary
        elide: Text.ElideRight
        maximumLineCount: 1
      }
    }

    RowLayout {
      id: controlsRow
      spacing: Math.round(Style.marginXS * widgetScale)
      z: 10
      visible: root.showButtons
      Layout.alignment: root.showAlbumArt ? Qt.AlignVCenter : Qt.AlignCenter

      NIconButton {
        visible: showPrev
        baseSize: Math.round(32 * widgetScale)
        icon: "media-prev"
        enabled: hasPlayer && MediaService.canGoPrevious
        colorBg: Color.mSurfaceVariant
        colorFg: enabled ? Color.mPrimary : Color.mOnSurfaceVariant
        customRadius: Math.round(Style.radiusS * widgetScale)
        onClicked: {
          if (enabled)
            MediaService.previous();
        }
      }

      NIconButton {
        baseSize: Math.round(36 * widgetScale)
        icon: isPlaying ? "media-pause" : "media-play"
        enabled: hasPlayer && (MediaService.canPlay || MediaService.canPause)
        colorBg: Color.mPrimary
        colorFg: Color.mOnPrimary
        colorBgHover: Qt.lighter(Color.mPrimary, 1.1)
        colorFgHover: Color.mOnPrimary
        customRadius: Math.round(Style.radiusS * widgetScale)
        onClicked: {
          if (enabled) {
            MediaService.playPause();
          }
        }
      }

      NIconButton {
        visible: showNext
        baseSize: Math.round(32 * widgetScale)
        icon: "media-next"
        enabled: hasPlayer && MediaService.canGoNext
        colorBg: Color.mSurfaceVariant
        colorFg: enabled ? Color.mPrimary : Color.mOnSurfaceVariant
        customRadius: Math.round(Style.radiusS * widgetScale)
        onClicked: {
          if (enabled)
            MediaService.next();
        }
      }
    }
  }
}
