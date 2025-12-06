import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.Bar.Extras
import qs.Modules.Panels.Settings
import qs.Services.System
import qs.Services.UI
import qs.Widgets

Rectangle {
  id: root

  property ShellScreen screen

  // Widget properties passed from Bar.qml for per-instance settings
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var widgetMetadata: BarWidgetRegistry.widgetMetadata[widgetId]
  property var widgetSettings: {
    if (section && sectionWidgetIndex >= 0) {
      var widgets = Settings.data.bar.widgets[section];
      if (widgets && sectionWidgetIndex < widgets.length) {
        return widgets[sectionWidgetIndex];
      }
    }
    return {};
  }

  readonly property string barPosition: Settings.data.bar.position
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"
  readonly property bool density: Settings.data.bar.density

  readonly property bool usePrimaryColor: widgetSettings.usePrimaryColor !== undefined ? widgetSettings.usePrimaryColor : widgetMetadata.usePrimaryColor
  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats
  readonly property bool showDiskUsage: (widgetSettings.showDiskUsage !== undefined) ? widgetSettings.showDiskUsage : widgetMetadata.showDiskUsage
  readonly property string diskPath: (widgetSettings.diskPath !== undefined) ? widgetSettings.diskPath : widgetMetadata.diskPath

  readonly property real iconSize: textSize * 1.4
  readonly property real textSize: {
    var base = isVertical ? width * 0.82 : height;
    return Math.max(1, (density === "compact") ? base * 0.43 : base * 0.33);
  }

  // Match Workspace widget pill sizing: base ratio depends on bar density
  readonly property real pillBaseRatio: (density === "compact") ? 0.85 : 0.65
  readonly property real pillHeight: Style.capsuleHeight * pillBaseRatio

  // Highlight colors
  readonly property color warningColor: Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.warningColor || Color.mTertiary) : Color.mTertiary
  readonly property color criticalColor: Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.criticalColor || Color.mError) : Color.mError

  readonly property int percentTextWidth: Math.ceil(percentMetrics.boundingRect.width + 3)
  readonly property int tempTextWidth: Math.ceil(tempMetrics.boundingRect.width + 3)
  readonly property int memTextWidth: Math.ceil(memMetrics.boundingRect.width + 3)
  readonly property color textColor: usePrimaryColor ? Color.mPrimary : Color.mOnSurface

  // Threshold settings from global configuration
  readonly property int cpuWarningThreshold: Settings.data.systemMonitor.cpuWarningThreshold
  readonly property int cpuCriticalThreshold: Settings.data.systemMonitor.cpuCriticalThreshold
  readonly property int tempWarningThreshold: Settings.data.systemMonitor.tempWarningThreshold
  readonly property int tempCriticalThreshold: Settings.data.systemMonitor.tempCriticalThreshold
  readonly property int memWarningThreshold: Settings.data.systemMonitor.memWarningThreshold
  readonly property int memCriticalThreshold: Settings.data.systemMonitor.memCriticalThreshold
  readonly property int diskWarningThreshold: Settings.data.systemMonitor.diskWarningThreshold
  readonly property int diskCriticalThreshold: Settings.data.systemMonitor.diskCriticalThreshold

  // Warning threshold calculation properties
  readonly property bool cpuWarning: showCpuUsage && SystemStatService.cpuUsage > cpuWarningThreshold
  readonly property bool cpuCritical: showCpuUsage && SystemStatService.cpuUsage > cpuCriticalThreshold
  readonly property bool tempWarning: showCpuTemp && SystemStatService.cpuTemp > tempWarningThreshold
  readonly property bool tempCritical: showCpuTemp && SystemStatService.cpuTemp > tempCriticalThreshold
  readonly property bool memWarning: showMemoryUsage && SystemStatService.memPercent > memWarningThreshold
  readonly property bool memCritical: showMemoryUsage && SystemStatService.memPercent > memCriticalThreshold
  readonly property bool diskWarning: showDiskUsage && SystemStatService.diskPercents[diskPath] > diskWarningThreshold
  readonly property bool diskCritical: showDiskUsage && SystemStatService.diskPercents[diskPath] > diskCriticalThreshold

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
  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(mainGrid.implicitWidth + Style.marginM * 2)
  implicitHeight: isVertical ? Math.round(mainGrid.implicitHeight + Style.marginM * 2) : Style.capsuleHeight
  radius: Style.radiusM
  color: Style.capsuleColor

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": I18n.tr("context-menu.widget-settings"),
        "action": "widget-settings",
        "icon": "settings"
      },
    ]

    onTriggered: action => {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.close();
                   }

                   if (action === "widget-settings") {
                     BarService.openWidgetSettings(screen, section, sectionWidgetIndex, widgetId, widgetSettings);
                   }
                 }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    onClicked: mouse => {
                 if (mouse.button === Qt.RightButton) {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.showContextMenu(contextMenu);
                     const pos = BarService.getContextMenuPosition(root, contextMenu.implicitWidth, contextMenu.implicitHeight);
                     contextMenu.openAtItem(root, pos.x, pos.y);
                   }
                 }
               }
  }

  // Status indicator component definition
  Component {
    id: statusIndicatorComponent

    Rectangle {
      id: statusIndicator
      property bool warning: false
      property bool critical: false
      property int indicatorWidth: Style.capsuleHeight
      property color warningColor: Color.mTertiary
      property color criticalColor: Color.mError

      width: isVertical ? Math.max(0, indicatorWidth - Style.marginS * 2) : Math.max(0, indicatorWidth + Style.marginXS * 2)
      height: isVertical ? Math.max(0, Style.capsuleHeight + Style.marginXS * 2) : pillHeight
      radius: Style.radiusM
      // Hide the rectangular indicator when the bar is vertical; keep it available for horizontal layout
      visible: !root.isVertical
      color: critical ? criticalColor : warningColor
      scale: (warning || critical) ? 1.0 : 0.0
      opacity: (warning || critical) ? 1.0 : 0.0

      // Smooth appearance/disappearance animation
      Behavior on scale {
        NumberAnimation {
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
      }

      Behavior on opacity {
        NumberAnimation {
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
      }

      Behavior on color {
        ColorAnimation {
          duration: Style.animationNormal
          easing.type: Easing.OutCubic
        }
      }
    }
  }

  GridLayout {
    id: mainGrid
    anchors.centerIn: parent
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: isVertical ? -1 : 1
    columns: isVertical ? 1 : -1
    rowSpacing: isVertical ? (Style.marginM) : 0
    columnSpacing: isVertical ? 0 : (Style.marginM)

    // CPU Usage Component
    Item {
      id: cpuUsageContainer
      Layout.preferredWidth: isVertical ? root.width : iconSize + percentTextWidth + (Style.marginXXS)
      Layout.preferredHeight: Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuUsage

      // Status indicator covering the entire component
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent

        onLoaded: {
          item.warning = Qt.binding(() => cpuWarning);
          item.critical = Qt.binding(() => cpuCritical);
          item.indicatorWidth = Qt.binding(() => cpuUsageContainer.width);
          item.warningColor = Qt.binding(() => root.warningColor);
          item.criticalColor = Qt.binding(() => root.criticalColor);
        }
      }

      GridLayout {
        id: cpuUsageContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: Style.marginXXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "cpu-usage"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // Invert color to bar background when indicator active
            color: isVertical ? (cpuCritical ? criticalColor : (cpuWarning ? warningColor : Color.mOnSurface)) : ((cpuWarning || cpuCritical) ? Color.mSurfaceVariant : Color.mOnSurface)
          }
        }

        NText {
          text: {
            let usage = Math.round(SystemStatService.cpuUsage);
            if (usage < 100) {
              return `${usage}%`;
            } else {
              return usage;
            }
          }
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : percentTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when indicator active
          color: isVertical ? (cpuCritical ? criticalColor : (cpuWarning ? warningColor : textColor)) : ((cpuWarning || cpuCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // CPU Temperature Component
    Item {
      id: cpuTempContainer
      Layout.preferredWidth: isVertical ? root.width : (iconSize + tempTextWidth) + (Style.marginXXS)
      Layout.preferredHeight: Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuTemp

      // Status indicator covering the entire component
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent

        onLoaded: {
          item.warning = Qt.binding(() => tempWarning);
          item.critical = Qt.binding(() => tempCritical);
          item.indicatorWidth = Qt.binding(() => cpuTempContainer.width);
          item.warningColor = Qt.binding(() => root.warningColor);
          item.criticalColor = Qt.binding(() => root.criticalColor);
        }
      }

      GridLayout {
        id: cpuTempContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: Style.marginXXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "cpu-temperature"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // Invert color when temp indicator active
            color: isVertical ? (tempCritical ? criticalColor : (tempWarning ? warningColor : Color.mOnSurface)) : ((tempWarning || tempCritical) ? Color.mSurfaceVariant : Color.mOnSurface)
          }
        }

        NText {
          text: `${Math.round(SystemStatService.cpuTemp)}°`
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : tempTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when temp indicator active
          color: isVertical ? (tempCritical ? criticalColor : (tempWarning ? warningColor : textColor)) : ((tempWarning || tempCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Memory Usage Component
    Item {
      id: memoryContainer
      Layout.preferredWidth: isVertical ? root.width : iconSize + (showMemoryAsPercent ? percentTextWidth : memTextWidth) + (Style.marginXXS)
      Layout.preferredHeight: Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showMemoryUsage

      // Status indicator covering the entire component
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent

        onLoaded: {
          item.warning = Qt.binding(() => memWarning);
          item.critical = Qt.binding(() => memCritical);
          item.indicatorWidth = Qt.binding(() => memoryContainer.width);
          item.warningColor = Qt.binding(() => root.warningColor);
          item.criticalColor = Qt.binding(() => root.criticalColor);
        }
      }

      GridLayout {
        id: memoryContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: Style.marginXXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "memory"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // Invert color when memory indicator active
            color: isVertical ? (memCritical ? criticalColor : (memWarning ? warningColor : Color.mOnSurface)) : ((memWarning || memCritical) ? Color.mSurfaceVariant : Color.mOnSurface)
          }
        }

        NText {
          text: showMemoryAsPercent ? `${Math.round(SystemStatService.memPercent)}%` : `${SystemStatService.memGb.toFixed(1)}G`
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : (showMemoryAsPercent ? percentTextWidth : memTextWidth)
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when memory indicator active
          color: isVertical ? (memCritical ? criticalColor : (memWarning ? warningColor : textColor)) : ((memWarning || memCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Network Download Speed Component
    Item {
      Layout.preferredWidth: isVertical ? root.width : iconSize + memTextWidth + (Style.marginXXS)
      Layout.preferredHeight: Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: downloadContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: Style.marginXXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "download-speed"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
          }
        }

        NText {
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.rxSpeed) : SystemStatService.formatSpeed(SystemStatService.rxSpeed)
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : memTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Network Upload Speed Component
    Item {
      Layout.preferredWidth: isVertical ? root.width : iconSize + memTextWidth + (Style.marginXXS)
      Layout.preferredHeight: Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: uploadContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: Style.marginXXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "upload-speed"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
          }
        }

        NText {
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.txSpeed) : SystemStatService.formatSpeed(SystemStatService.txSpeed)
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : memTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }
    }

    // Disk Usage Component (primary drive)
    Item {
      id: diskContainer
      Layout.preferredWidth: isVertical ? root.width : iconSize + percentTextWidth + (Style.marginXXS)
      Layout.preferredHeight: Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showDiskUsage

      // Status indicator covering the entire component
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent

        onLoaded: {
          item.warning = Qt.binding(() => diskWarning);
          item.critical = Qt.binding(() => diskCritical);
          item.indicatorWidth = Qt.binding(() => diskContainer.width);
          item.warningColor = Qt.binding(() => root.warningColor);
          item.criticalColor = Qt.binding(() => root.criticalColor);
        }
      }

      GridLayout {
        id: diskContent
        anchors.centerIn: parent
        flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: isVertical ? 2 : 1
        columns: isVertical ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: Style.marginXXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: isVertical ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "storage"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // Invert color when disk indicator active (vertical uses highlight colors)
            color: isVertical ? (diskCritical ? criticalColor : (diskWarning ? warningColor : Color.mOnSurface)) : ((diskWarning || diskCritical) ? Color.mSurfaceVariant : Color.mOnSurface)
          }
        }

        NText {
          id: toto
          text: SystemStatService.diskPercents[diskPath] ? `${SystemStatService.diskPercents[diskPath]}%` : "n/a"
          family: Settings.data.ui.fontFixed
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          Layout.preferredWidth: isVertical ? -1 : percentTextWidth
          horizontalAlignment: isVertical ? Text.AlignHCenter : Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when disk indicator active
          color: isVertical ? (diskCritical ? criticalColor : (diskWarning ? warningColor : textColor)) : ((diskWarning || diskCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: {
          TooltipService.show(diskContent, diskPath, BarService.getTooltipDirection());
        }
        onExited: {
          TooltipService.hide();
        }
      }
    }
  }
}
