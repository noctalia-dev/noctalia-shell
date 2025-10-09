import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen
  property real scaling: 1.0

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

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

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property bool compact: (Settings.data.bar.density === "compact")

  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats
  readonly property bool showDiskUsage: (widgetSettings.showDiskUsage !== undefined) ? widgetSettings.showDiskUsage : widgetMetadata.showDiskUsage

  readonly property real iconSize: textSize * 1.4
  readonly property real textSize: {
    var base = isVertical ? width * 0.82 : height
    return Math.max(1, compact ? base * 0.43 : base * 0.33)
  }

  readonly property int percentTextWidth: Math.ceil(percentMetrics.boundingRect.width + 3 * scaling)
  readonly property int tempTextWidth: Math.ceil(tempMetrics.boundingRect.width + 3 * scaling)
  readonly property int memTextWidth: Math.ceil(memMetrics.boundingRect.width + 3 * scaling)

  TextMetrics {
    id: percentMetrics
    font.family: Settings.data.ui.fontFixed
    font.weight: Style.fontWeightMedium
    font.pointSize: textSize * Settings.data.ui.fontFixedScale
    text: "99%" // Use the longest possible string for measurement
  }

  TextMetrics {
    id: tempMetrics
    font.family: Settings.data.ui.fontFixed
    font.weight: Style.fontWeightMedium
    font.pointSize: textSize * Settings.data.ui.fontFixedScale
    text: "99°" // Use the longest possible string for measurement
  }

  TextMetrics {
    id: memMetrics
    font.family: Settings.data.ui.fontFixed
    font.weight: Style.fontWeightMedium
    font.pointSize: textSize * Settings.data.ui.fontFixedScale
    text: "99.9K" // Longest value part of network speed
  }

  anchors.centerIn: parent
  implicitWidth: isVertical ? Math.round(Style.capsuleHeight * scaling) : Math.round(mainGrid.implicitWidth + Style.marginM * 2 * scaling)
  implicitHeight: isVertical ? Math.round(mainGrid.implicitHeight + Style.marginM * 2 * scaling) : Math.round(Style.capsuleHeight * scaling)
  radius: Math.round(Style.radiusM * scaling)
  color: Settings.data.bar.showCapsule ? Color.mSurfaceVariant : Color.transparent

  GridLayout {
    id: mainGrid
    anchors.centerIn: parent
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: isVertical ? -1 : 1
    columns: isVertical ? 1 : -1
    rowSpacing: isVertical ? (Style.marginM * scaling) : 0
    columnSpacing: isVertical ? 0 : (Style.marginM * scaling)

    // CPU Usage Component
    Item {
      Layout.preferredWidth: isVertical ? root.width : iconSize + percentTextWidth + (Style.marginXXS * scaling)
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuUsage

      GridLayout {
        id: cpuUsageContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NIcon {
          icon: "cpu-usage"
          pointSize: iconSize
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }

        NText {
          text: `${Math.round(SystemStatService.cpuUsage)}%`
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : percentTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // CPU Temperature Component
    Item {
      Layout.preferredWidth: isVertical ? root.width : (iconSize + tempTextWidth) + (Style.marginXXS * scaling)
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuTemp

      GridLayout {
        id: cpuTempContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NIcon {
          icon: "cpu-temperature"
          pointSize: iconSize
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }

        NText {
          text: `${Math.round(SystemStatService.cpuTemp)}°`
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : tempTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Memory Usage Component
    Item {
      Layout.preferredWidth: isVertical ? root.width : iconSize + (showMemoryAsPercent ? percentTextWidth : memTextWidth) + (Style.marginXXS * scaling)
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showMemoryUsage

      GridLayout {
        id: memoryContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NIcon {
          icon: "memory"
          pointSize: iconSize
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }

        NText {
          text: showMemoryAsPercent ? `${Math.round(SystemStatService.memPercent)}%` : `${SystemStatService.memGb.toFixed(1)}G`
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : (showMemoryAsPercent ? percentTextWidth : memTextWidth)
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Network Download Speed Component
    Item {
      Layout.preferredWidth: isVertical ? root.width : iconSize + memTextWidth + (Style.marginXXS * scaling)
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: downloadContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NIcon {
          icon: "download-speed"
          pointSize: iconSize
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }

        NText {
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.rxSpeed) : SystemStatService.formatSpeed(SystemStatService.rxSpeed)
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : memTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Network Upload Speed Component
    Item {
      Layout.preferredWidth: isVertical ? root.width : iconSize + memTextWidth + (Style.marginXXS * scaling)
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: uploadContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NIcon {
          icon: "upload-speed"
          pointSize: iconSize
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }

        NText {
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.txSpeed) : SystemStatService.formatSpeed(SystemStatService.txSpeed)
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : memTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Disk Usage Component (primary drive)
    Item {
      Layout.preferredWidth: isVertical ? root.width : iconSize + percentTextWidth + (Style.marginXXS * scaling)
      Layout.preferredHeight: Math.round(Style.capsuleHeight * scaling)
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showDiskUsage

      GridLayout {
        id: diskContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS * scaling
        columnSpacing: Style.marginXXS * scaling

        NIcon {
          icon: "storage"
          pointSize: iconSize
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
        }

        NText {
          text: `${SystemStatService.diskPercent}%`
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : percentTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: Color.mPrimary
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }
  }
}
