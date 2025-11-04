import QtQuick
import Quickshell
import qs.Commons
import qs.Modules.AudioSpectrum
import qs.Services
import qs.Widgets

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property bool isVerticalBar: (Settings.data.bar.position === "left" || Settings.data.bar.position === "right")

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section]
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex]
      }
    }
    return {}
  }

  // Resolve settings: try user settings or defaults from BarWidgetRegistry
  readonly property int visualizerWidth: widgetSettings.width !== undefined ? widgetSettings.width : widgetMetadata.width
  readonly property bool hideWhenIdle: widgetSettings.hideWhenIdle !== undefined ? widgetSettings.hideWhenIdle : widgetMetadata.hideWhenIdle
  readonly property string colorName: widgetSettings.colorName !== undefined ? widgetSettings.colorName : widgetMetadata.colorName

  readonly property color fillColor: {
    switch (colorName) {
    case "primary":
      return Color.mPrimary
    case "secondary":
      return Color.mSecondary
    case "tertiary":
      return Color.mTertiary
    case "error":
      return Color.mError
    case "onSurface":
    default:
      return Color.mOnSurface
    }
  }

  readonly property bool shouldShow: (currentVisualizerType !== "" && currentVisualizerType !== "none") && (!hideWhenIdle || MediaService.isPlaying)

  implicitWidth: !shouldShow ? 0 : isVerticalBar ? Style.capsuleHeight : visualizerWidth
  implicitHeight: !shouldShow ? 0 : isVerticalBar ? visualizerWidth : Style.capsuleHeight
  visible: shouldShow

  Behavior on implicitWidth {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }
  Behavior on implicitHeight {
    NumberAnimation {
      duration: Style.animationNormal
      easing.type: Easing.InOutCubic
    }
  }

  Rectangle {
    id: background
    anchors.fill: parent
    radius: Style.radiusS
    color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent
  }

  // Store visualizer type to force re-evaluation
  readonly property string currentVisualizerType: Settings.data.audio.visualizerType

  // When visualizer type or playback changes, shouldShow updates automatically
  // The Loader dynamically loads the appropriate visualizer based on settings
  Loader {
    id: visualizerLoader
    anchors.fill: parent
    anchors.margins: Style.marginS
    active: shouldShow
    asynchronous: true

    sourceComponent: {
      switch (currentVisualizerType) {
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
  }

  // Click to cycle through visualizer types
  MouseArea {
    id: mouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    onClicked: mouse => {
                 const types = ["linear", "mirrored", "wave"]
                 const currentIndex = types.indexOf(currentVisualizerType)
                 const nextIndex = (currentIndex + 1) % types.length
                 const newType = types[nextIndex]

                 // Update settings directly, maybe this should be a widget setting...
                 Settings.data.audio.visualizerType = newType
               }
  }

  Component {
    id: linearComponent
    LinearSpectrum {
      anchors.fill: parent
      values: CavaService.values
      fillColor: root.fillColor
      showMinimumSignal: true
      vertical: root.isVerticalBar
    }
  }

  Component {
    id: mirroredComponent
    MirroredSpectrum {
      anchors.fill: parent
      values: CavaService.values
      fillColor: root.fillColor
      showMinimumSignal: true
      vertical: root.isVerticalBar
    }
  }

  Component {
    id: waveComponent
    WaveSpectrum {
      anchors.fill: parent
      values: CavaService.values
      fillColor: root.fillColor
      showMinimumSignal: true
      vertical: root.isVerticalBar
    }
  }
}
