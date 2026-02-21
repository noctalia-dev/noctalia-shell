import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Services.Media
import qs.Services.UI
import qs.Widgets
import qs.Widgets.AudioSpectrum

Item {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  // Explicit screenName property ensures reactive binding when screen changes
  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVerticalBar: barPosition === "left" || barPosition === "right"
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0 && screenName) {
      var widgets = Settings.getBarWidgetsForScreen(screenName)[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  // Resolve settings: try user settings or defaults from BarWidgetRegistry
  readonly property int visualizerWidth: widgetSettings.width !== undefined ? widgetSettings.width : widgetMetadata.width
  readonly property bool hideWhenIdle: widgetSettings.hideWhenIdle !== undefined ? widgetSettings.hideWhenIdle : widgetMetadata.hideWhenIdle
  readonly property string colorName: widgetSettings.colorName !== undefined ? widgetSettings.colorName : widgetMetadata.colorName

  readonly property color fillColor: Color.resolveColorKey(colorName)

  readonly property bool shouldShow: (currentVisualizerType !== "" && currentVisualizerType !== "none") && (!hideWhenIdle || MediaService.isPlaying)

  // Register/unregister with CavaService based on visibility
  readonly property string cavaComponentId: "bar:audiovisualizer:" + root.screen.name + ":" + root.section + ":" + root.sectionWidgetIndex

  onShouldShowChanged: {
    if (root.shouldShow) {
      CavaService.registerComponent(root.cavaComponentId);
    } else {
      CavaService.unregisterComponent(root.cavaComponentId);
    }
  }

  Component.onDestruction: {
    if (root.shouldShow) {
      CavaService.unregisterComponent(root.cavaComponentId);
    }
  }

  // Content dimensions for implicit sizing
  readonly property real contentWidth: !shouldShow ? 0 : isVerticalBar ? capsuleHeight : visualizerWidth
  readonly property real contentHeight: !shouldShow ? 0 : isVerticalBar ? visualizerWidth : capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight
  visible: shouldShow
  opacity: shouldShow ? 1.0 : 0.0

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

  // Store visualizer type to force re-evaluation
  readonly property string currentVisualizerType: Settings.data.audio.visualizerType

  // Visual capsule centered in parent
  Rectangle {
    id: background
    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent
    radius: Style.radiusS
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

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

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("actions.cycle-visualizer"),
        "action": "cycle-visualizer",
        "icon": "chart-column"
      },
      {
        "label": I18n.tr("actions.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   contextMenu.close();
                   PanelService.closeContextMenu(screen);

                   if (action === "cycle-visualizer") {
                     const types = ["linear", "mirrored", "wave"];
                     const currentIndex = types.indexOf(currentVisualizerType);
                     const nextIndex = (currentIndex + 1) % types.length;
                     Settings.data.audio.visualizerType = types[nextIndex];
                   } else if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  // Click to cycle through visualizer types
  MouseArea {
    id: mouseArea
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   PanelService.showContextMenu(contextMenu, root, screen);
                 } else {
                   const types = ["linear", "mirrored", "wave"];
                   const currentIndex = types.indexOf(currentVisualizerType);
                   const nextIndex = (currentIndex + 1) % types.length;
                   Settings.data.audio.visualizerType = types[nextIndex];
                 }
               }
  }

  Component {
    id: linearComponent
    NLinearSpectrum {
      anchors.fill: parent
      values: CavaService.values
      fillColor: root.fillColor
      showMinimumSignal: true
      vertical: root.isVerticalBar
      barPosition: root.barPosition
    }
  }

  Component {
    id: mirroredComponent
    NMirroredSpectrum {
      anchors.fill: parent
      values: CavaService.values
      fillColor: root.fillColor
      showMinimumSignal: true
      vertical: root.isVerticalBar
    }
  }

  Component {
    id: waveComponent
    NWaveSpectrum {
      anchors.fill: parent
      values: CavaService.values
      fillColor: root.fillColor
      showMinimumSignal: true
      vertical: root.isVerticalBar
    }
  }
}
