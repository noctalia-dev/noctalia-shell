import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.Media
import qs.Services.UI
import qs.Widgets
import qs.Widgets.AudioSpectrum

DraggableDesktopWidget {
  id: root

  defaultY: 280

  readonly property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["AudioVisualizer"]

  readonly property int visualizerWidth: (widgetData && widgetData.width !== undefined) ? widgetData.width : (widgetMetadata?.width ?? 320)
  readonly property int visualizerHeight: (widgetData && widgetData.height !== undefined) ? widgetData.height : (widgetMetadata?.height ?? 72)
  readonly property string visualizerType: (widgetData && widgetData.visualizerType !== undefined) ? widgetData.visualizerType : (widgetMetadata?.visualizerType ?? "linear")
  readonly property bool hideWhenIdle: (widgetData && widgetData.hideWhenIdle !== undefined) ? widgetData.hideWhenIdle : (widgetMetadata?.hideWhenIdle ?? false)
  readonly property string colorName: (widgetData && widgetData.colorName !== undefined) ? widgetData.colorName : (widgetMetadata?.colorName ?? "primary")

  readonly property color fillColor: Color.resolveColorKey(colorName)

  readonly property bool shouldShow: visualizerType !== "" && visualizerType !== "none" && (!hideWhenIdle || MediaService.isPlaying)
  readonly property bool isHidden: !shouldShow
  readonly property bool shouldRegisterSpectrum: shouldShow

  // Keep widget visible in edit mode so users can move/configure it
  visible: !root.isHidden || DesktopWidgetRegistry.editMode

  readonly property string spectrumComponentId: "desktop:audiovisualizer:" + (root.screen ? root.screen.name : "unknown") + ":" + root.widgetIndex

  onShouldRegisterSpectrumChanged: {
    if (root.shouldRegisterSpectrum) {
      SpectrumService.registerComponent(root.spectrumComponentId);
    } else {
      SpectrumService.unregisterComponent(root.spectrumComponentId);
    }
  }

  Component.onCompleted: {
    if (root.shouldRegisterSpectrum) {
      SpectrumService.registerComponent(root.spectrumComponentId);
    }
  }

  Component.onDestruction: {
    SpectrumService.unregisterComponent(root.spectrumComponentId);
  }

  implicitWidth: Math.round(visualizerWidth * widgetScale)
  implicitHeight: Math.round(visualizerHeight * widgetScale)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: visualizerMask
    anchors.fill: parent
    color: "transparent"
    radius: root.roundedCorners ? Math.min(Math.round(Style.radiusL * root.widgetScale), Style.radiusL, width / 2, height / 2) : 0
    clip: true

    Loader {
      id: visualizerLoader
      anchors.fill: parent
      anchors.margins: root.showBackground ? Math.round(Style.marginXS * root.widgetScale) : 0
      active: root.shouldShow
      asynchronous: true

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
    }
  }

  Component {
    id: linearComponent
    NLinearSpectrum {
      anchors.fill: parent
      values: SpectrumService.values
      fillColor: root.fillColor
      showMinimumSignal: true
    }
  }

  Component {
    id: mirroredComponent
    NMirroredSpectrum {
      anchors.fill: parent
      values: SpectrumService.values
      fillColor: root.fillColor
      showMinimumSignal: true
    }
  }

  Component {
    id: waveComponent
    NWaveSpectrum {
      anchors.fill: parent
      values: SpectrumService.values
      fillColor: root.fillColor
      showMinimumSignal: true
    }
  }
}
