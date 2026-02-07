import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Services.System
import qs.Services.UI
import qs.Widgets

DraggableDesktopWidget {
  id: root

  // Widget settings
  readonly property var widgetMetadata: DesktopWidgetRegistry.widgetMetadata["SystemStat"]
  readonly property string statType: (widgetData && widgetData.statType !== undefined) ? widgetData.statType : (widgetMetadata.statType !== undefined ? widgetMetadata.statType : "CPU")
  readonly property string diskPath: (widgetData && widgetData.diskPath !== undefined) ? widgetData.diskPath : "/"
  readonly property string layout: (widgetData && widgetData.layout !== undefined) ? widgetData.layout : (widgetMetadata.layout !== undefined ? widgetMetadata.layout : "side")

  // Fixed colors
  readonly property color color: Color.mPrimary
  readonly property color color2: Color.mSecondary

  // Legend items model - each item has: text, color, icon (optional), bold (optional), opacity (optional), elide (optional)
  readonly property var legendItems: {
    switch (root.statType) {
    case "CPU":
      return [
            {
              icon: "cpu-usage",
              text: Math.round(SystemStatService.cpuUsage) + "%",
              color: root.color
            },
            {
              text: "cpu-usage",
              text: SystemStatService.cpuFreq,
              color: root.color,
              opacity: 0.8
            },
            {
              icon: "cpu-temperature",
              text: SystemStatService.cpuTemp + "°C",
              color: root.color2
            }
          ];
    case "GPU":
      return [
            {
              icon: "gpu-temperature",
              text: Math.round(SystemStatService.gpuTemp) + "°C",
              color: root.color
            }
          ];
    case "Memory":
      return [
            {
              icon: "memory",
              text: Math.round(SystemStatService.memPercent) + "%",
              color: root.color
            }
          ];
    case "Disk":
      var items = [
            {
              icon: "storage",
              text: Math.round(SystemStatService.diskPercents[root.diskPath] || 0) + "%",
              color: root.color
            }
          ];
      if (root.diskPath !== "/") {
        items.push({
                     text: root.diskPath,
                     color: root.color,
                     opacity: 0.8,
                     elide: true
                   });
      }
      return items;
    case "Network":
      return [
            {
              icon: "download-speed",
              text: SystemStatService.formatSpeed(SystemStatService.rxSpeed),
              color: root.color
            },
            {
              icon: "upload-speed",
              text: SystemStatService.formatSpeed(SystemStatService.txSpeed),
              color: root.color2
            }
          ];
    default:
      return [];
    }
  }

  // History from service
  readonly property var history: {
    switch (root.statType) {
    case "CPU":
      return SystemStatService.cpuHistory;
    case "GPU":
      return SystemStatService.gpuTempHistory;
    case "Memory":
      return SystemStatService.memHistory;
    case "Disk":
      return SystemStatService.diskHistories[root.diskPath] || [];
    case "Network":
      return SystemStatService.rxSpeedHistory;
    default:
      return [];
    }
  }

  // Secondary history (CPU temp for CPU, Tx for Network)
  readonly property var history2: {
    switch (root.statType) {
    case "CPU":
      return SystemStatService.cpuTempHistory;
    case "Network":
      return SystemStatService.txSpeedHistory;
    default:
      return [];
    }
  }

  // Graph min/max values
  readonly property real graphMinValue: root.statType === "GPU" ? Math.max(SystemStatService.gpuTempHistoryMin - 5, 0) : 0
  readonly property real graphMaxValue: {
    switch (root.statType) {
    case "CPU":
    case "Memory":
    case "Disk":
      return 100;  // Percentage-based stats use fixed 0-100 range
    case "GPU":
      return Math.max(SystemStatService.gpuTempHistoryMax + 5, 1);
    case "Network":
      return SystemStatService.rxMaxSpeed;
    default:
      return 100;
    }
  }
  readonly property real graphMinValue2: {
    switch (root.statType) {
    case "CPU":
      return Math.max(SystemStatService.cpuTempHistoryMin - 5, 0);
    default:
      return graphMinValue;
    }
  }
  readonly property real graphMaxValue2: {
    switch (root.statType) {
    case "CPU":
      return Math.max(SystemStatService.cpuTempHistoryMax + 5, 1);
    case "Network":
      return SystemStatService.txMaxSpeed;
    default:
      return graphMaxValue;
    }
  }

  implicitWidth: Math.round(240 * widgetScale)
  implicitHeight: Math.round(120 * widgetScale)
  width: implicitWidth
  height: implicitHeight

  // Update interval per stat type
  readonly property int graphUpdateInterval: {
    switch (root.statType) {
    case "CPU":
      return Settings.data.systemMonitor.cpuPollingInterval;
    case "GPU":
      return Settings.data.systemMonitor.gpuPollingInterval;
    case "Memory":
      return Settings.data.systemMonitor.memPollingInterval;
    case "Disk":
      return Settings.data.systemMonitor.diskPollingInterval;
    case "Network":
      return Settings.data.systemMonitor.networkPollingInterval;
    default:
      return 1000;
    }
  }

  // Graph component (shared between layouts)
  Component {
    id: graphComponent
    NGraph {
      values: root.history
      values2: root.history2
      minValue: root.graphMinValue
      maxValue: root.graphMaxValue
      minValue2: root.graphMinValue2
      maxValue2: root.graphMaxValue2
      color: root.color
      color2: root.color2
      fill: true
      updateInterval: root.graphUpdateInterval
      animateScale: root.statType === "Network"
    }
  }

  // Side layout: icon + legend on left, graph on right
  RowLayout {
    anchors.fill: parent
    anchors.margins: Math.round(Style.marginM * widgetScale)
    spacing: Math.round(Style.marginL * widgetScale)
    visible: root.layout === "side"

    ColumnLayout {
      Layout.alignment: Qt.AlignVCenter
      Layout.fillHeight: true
      Layout.preferredWidth: Math.round(64 * widgetScale)
      spacing: Style.marginXS * root.widgetScale

      Repeater {
        model: root.legendItems
        delegate: RowLayout {
          Layout.alignment: Qt.AlignHCenter
          spacing: Math.round(Style.marginXXS * root.widgetScale)

          NIcon {
            visible: !!modelData.icon
            icon: modelData.icon || ""
            color: modelData.color
            pointSize: Style.fontSizeS * root.widgetScale
            opacity: modelData.opacity !== undefined ? modelData.opacity : 1.0
          }

          NText {
            text: modelData.text
            color: modelData.color
            pointSize: Style.fontSizeS * root.widgetScale
            font.family: Settings.data.ui.fontFixed
            font.weight: modelData.bold ? Style.fontWeightBold : Style.fontWeightRegular
            opacity: modelData.opacity !== undefined ? modelData.opacity : 1.0
            elide: modelData.elide ? Text.ElideMiddle : Text.ElideNone
            Layout.maximumWidth: modelData.elide ? Math.round(56 * root.widgetScale) : -1
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }

    Loader {
      active: root.layout === "side"
      Layout.fillWidth: true
      Layout.fillHeight: true
      sourceComponent: graphComponent
    }
  }

  // Bottom layout: full-width graph, horizontal legend at bottom
  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Math.round(Style.marginM * widgetScale)
    spacing: Math.round(Style.marginS * widgetScale)
    visible: root.layout === "bottom"

    Loader {
      active: root.layout === "bottom"
      Layout.fillWidth: true
      Layout.fillHeight: true
      sourceComponent: graphComponent
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignHCenter
      spacing: Math.round(Style.marginM * widgetScale)

      Repeater {
        model: root.legendItems
        delegate: RowLayout {
          Layout.alignment: Qt.AlignVCenter
          spacing: Math.round(Style.marginXXS * root.widgetScale)

          NIcon {
            Layout.alignment: Qt.AlignVCenter
            visible: !!modelData.icon
            icon: modelData.icon || ""
            color: modelData.color
            pointSize: Style.fontSizeS * root.widgetScale
            opacity: modelData.opacity !== undefined ? modelData.opacity : 1.0
          }

          NText {
            Layout.alignment: Qt.AlignVCenter
            text: modelData.text
            color: modelData.color
            pointSize: Style.fontSizeS * root.widgetScale
            font.family: Settings.data.ui.fontFixed
            font.weight: modelData.bold ? Style.fontWeightBold : Style.fontWeightRegular
            opacity: modelData.opacity !== undefined ? modelData.opacity : 1.0
            elide: modelData.elide ? Text.ElideMiddle : Text.ElideNone
            Layout.maximumWidth: modelData.elide ? Math.round(56 * root.widgetScale) : -1
          }
        }
      }
    }
  }
}
