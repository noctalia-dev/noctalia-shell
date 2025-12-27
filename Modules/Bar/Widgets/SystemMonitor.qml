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

  readonly property bool compactMode: widgetSettings.compactMode !== undefined ? widgetSettings.compactMode : widgetMetadata.compactMode
  readonly property bool usePrimaryColor: widgetSettings.usePrimaryColor !== undefined ? widgetSettings.usePrimaryColor : widgetMetadata.usePrimaryColor
  readonly property bool useMonospaceFont: widgetSettings.useMonospaceFont !== undefined ? widgetSettings.useMonospaceFont : widgetMetadata.useMonospaceFont
  readonly property bool showCpuUsage: (widgetSettings.showCpuUsage !== undefined) ? widgetSettings.showCpuUsage : widgetMetadata.showCpuUsage
  readonly property bool showCpuTemp: (widgetSettings.showCpuTemp !== undefined) ? widgetSettings.showCpuTemp : widgetMetadata.showCpuTemp
  readonly property bool showGpuTemp: (widgetSettings.showGpuTemp !== undefined) ? widgetSettings.showGpuTemp : widgetMetadata.showGpuTemp
  readonly property bool showMemoryUsage: (widgetSettings.showMemoryUsage !== undefined) ? widgetSettings.showMemoryUsage : widgetMetadata.showMemoryUsage
  readonly property bool showMemoryAsPercent: (widgetSettings.showMemoryAsPercent !== undefined) ? widgetSettings.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  readonly property bool showNetworkStats: (widgetSettings.showNetworkStats !== undefined) ? widgetSettings.showNetworkStats : widgetMetadata.showNetworkStats
  readonly property bool showDiskUsage: (widgetSettings.showDiskUsage !== undefined) ? widgetSettings.showDiskUsage : widgetMetadata.showDiskUsage
  readonly property string diskPath: (widgetSettings.diskPath !== undefined) ? widgetSettings.diskPath : widgetMetadata.diskPath

  readonly property string fontFamily: useMonospaceFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault
  readonly property real iconSize: compactMode ? textSize * 1.2 : textSize * 1.4
  readonly property real textSize: {
    var base = isVertical ? width * 0.82 : height;
    return Math.max(1, (density === "compact") ? base * 0.43 : base * 0.33);
  }

  // Mini bar dimensions for compact mode
  readonly property real miniBarWidth: Math.max(16, Math.round(iconSize * 1.8))
  readonly property real miniBarHeight: Math.max(3, Math.round(iconSize * 0.25))

  // Network speed to bar value (log scale for compact mode)
  function getNetworkBarValue(bytesPerSecond) {
    if (bytesPerSecond <= 0)
      return 0;
    // Log scale: 1KB=0%, 1MB=50%, 100MB=100%
    const kb = bytesPerSecond / 1024;
    return Math.min(100, Math.max(0, (Math.log10(kb) / 5) * 100));
  }

  // Build comprehensive tooltip text with all stats
  function buildTooltipText() {
    let lines = [];

    // CPU
    lines.push(`${I18n.tr("system-monitor.cpu-usage")}: ${Math.round(SystemStatService.cpuUsage)}%`);
    if (SystemStatService.cpuTemp > 0) {
      lines.push(`${I18n.tr("system-monitor.cpu-temp")}: ${Math.round(SystemStatService.cpuTemp)}°C`);
    }

    // GPU (if available)
    if (SystemStatService.gpuAvailable) {
      lines.push(`${I18n.tr("system-monitor.gpu-temp")}: ${Math.round(SystemStatService.gpuTemp)}°C`);
    }

    // Memory
    lines.push(`${I18n.tr("system-monitor.memory")}: ${Math.round(SystemStatService.memPercent)}% (${SystemStatService.formatMemoryGb(SystemStatService.memGb)})`);

    // Network
    lines.push(`${I18n.tr("system-monitor.download-speed")}: ${SystemStatService.formatSpeed(SystemStatService.rxSpeed)}`);
    lines.push(`${I18n.tr("system-monitor.upload-speed")}: ${SystemStatService.formatSpeed(SystemStatService.txSpeed)}`);

    // Disk
    const diskPercent = SystemStatService.diskPercents[diskPath];
    if (diskPercent !== undefined) {
      const usedGb = SystemStatService.diskUsedGb[diskPath] || 0;
      const sizeGb = SystemStatService.diskSizeGb[diskPath] || 0;
      lines.push(`${I18n.tr("system-monitor.disk")}: ${usedGb.toFixed(1)}G / ${sizeGb.toFixed(1)}G (${diskPercent}%)`);
    }

    return lines.join("\n");
  }

  // Match Workspace widget pill sizing: base ratio depends on bar density
  readonly property real pillBaseRatio: (density === "compact") ? 0.85 : 0.65
  readonly property int pillHeight: Math.round(Style.capsuleHeight * pillBaseRatio)

  // Highlight colors
  readonly property color warningColor: Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.warningColor || Color.mTertiary) : Color.mTertiary
  readonly property color criticalColor: Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.criticalColor || Color.mError) : Color.mError

  readonly property color textColor: usePrimaryColor ? Color.mPrimary : Color.mOnSurface

  // Threshold settings from global configuration
  readonly property int cpuWarningThreshold: Settings.data.systemMonitor.cpuWarningThreshold
  readonly property int cpuCriticalThreshold: Settings.data.systemMonitor.cpuCriticalThreshold
  readonly property int tempWarningThreshold: Settings.data.systemMonitor.tempWarningThreshold
  readonly property int tempCriticalThreshold: Settings.data.systemMonitor.tempCriticalThreshold
  readonly property int gpuWarningThreshold: Settings.data.systemMonitor.gpuWarningThreshold
  readonly property int gpuCriticalThreshold: Settings.data.systemMonitor.gpuCriticalThreshold
  readonly property int memWarningThreshold: Settings.data.systemMonitor.memWarningThreshold
  readonly property int memCriticalThreshold: Settings.data.systemMonitor.memCriticalThreshold
  readonly property int diskWarningThreshold: Settings.data.systemMonitor.diskWarningThreshold
  readonly property int diskCriticalThreshold: Settings.data.systemMonitor.diskCriticalThreshold

  // Warning threshold calculation properties
  readonly property bool cpuWarning: showCpuUsage && SystemStatService.cpuUsage > cpuWarningThreshold
  readonly property bool cpuCritical: showCpuUsage && SystemStatService.cpuUsage > cpuCriticalThreshold
  readonly property bool tempWarning: showCpuTemp && SystemStatService.cpuTemp > tempWarningThreshold
  readonly property bool tempCritical: showCpuTemp && SystemStatService.cpuTemp > tempCriticalThreshold
  readonly property bool gpuWarning: showGpuTemp && SystemStatService.gpuAvailable && SystemStatService.gpuTemp > gpuWarningThreshold
  readonly property bool gpuCritical: showGpuTemp && SystemStatService.gpuAvailable && SystemStatService.gpuTemp > gpuCriticalThreshold
  readonly property bool memWarning: showMemoryUsage && SystemStatService.memPercent > memWarningThreshold
  readonly property bool memCritical: showMemoryUsage && SystemStatService.memPercent > memCriticalThreshold
  readonly property bool diskWarning: showDiskUsage && SystemStatService.diskPercents[diskPath] > diskWarningThreshold
  readonly property bool diskCritical: showDiskUsage && SystemStatService.diskPercents[diskPath] > diskCriticalThreshold

  anchors.centerIn: parent
  implicitWidth: isVertical ? Style.capsuleHeight : Math.round(mainGrid.implicitWidth + Style.marginM * 2)
  implicitHeight: isVertical ? Math.round(mainGrid.implicitHeight + Style.marginM * 2) : Style.capsuleHeight
  radius: Style.radiusM
  color: Style.capsuleColor
  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

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
    id: tooltipArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    hoverEnabled: true
    onClicked: mouse => {
                 if (mouse.button === Qt.LeftButton) {
                   PanelService.getPanel("systemStatsPanel", screen)?.toggle(root);
                   TooltipService.hide();
                 } else if (mouse.button === Qt.RightButton) {
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.showContextMenu(contextMenu);
                     contextMenu.openAtItem(root, screen);
                   }
                 }
               }
    onEntered: {
      TooltipService.show(root, buildTooltipText(), BarService.getTooltipDirection());
      tooltipRefreshTimer.start();
    }
    onExited: {
      tooltipRefreshTimer.stop();
      TooltipService.hide();
    }
  }

  Timer {
    id: tooltipRefreshTimer
    interval: 1000
    repeat: true
    onTriggered: {
      if (tooltipArea.containsMouse) {
        TooltipService.updateText(buildTooltipText());
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

  // Mini gauge component for compact mode, vertical gauge that fills from bottom
  Component {
    id: miniGaugeComponent

    Rectangle {
      id: miniGauge
      property real value: 0 // 0-100
      property bool warning: false
      property bool critical: false
      property color warningColor: Color.mTertiary
      property color criticalColor: Color.mError

      width: miniBarHeight // Thin vertical gauge
      height: iconSize
      radius: width / 2
      color: Qt.alpha(Color.mOnSurface, 0.3)

      // Fill that grows from bottom
      Rectangle {
        property real fillHeight: parent.height * Math.min(1, Math.max(0, miniGauge.value / 100))
        width: parent.width
        height: fillHeight
        radius: parent.radius
        color: miniGauge.critical ? miniGauge.criticalColor : (miniGauge.warning ? miniGauge.warningColor : Color.mPrimary)
        anchors.bottom: parent.bottom

        Behavior on fillHeight {
          enabled: !Settings.data.general.animationDisabled
          NumberAnimation {
            duration: Style.animationFast
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
  }

  GridLayout {
    id: mainGrid
    anchors.centerIn: parent
    flow: isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rows: isVertical ? -1 : 1
    columns: isVertical ? 1 : -1
    rowSpacing: isVertical ? (compactMode ? Style.marginL : Style.marginM) : 0
    columnSpacing: isVertical ? 0 : (Style.marginM)

    // CPU Usage Component
    Item {
      id: cpuUsageContainer
      implicitWidth: cpuUsageContent.implicitWidth
      implicitHeight: cpuUsageContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuUsage

      // Status indicator covering the entire component (only for non-compact mode)
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent
        visible: !compactMode

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
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "cpu-usage"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // In compact mode, use threshold colors for icon; otherwise use existing logic
            color: compactMode ? (cpuCritical ? criticalColor : (cpuWarning ? warningColor : Color.mOnSurface)) : (isVertical ? (cpuCritical ? criticalColor : (cpuWarning ? warningColor : Color.mOnSurface)) : ((cpuWarning || cpuCritical) ? Color.mSurfaceVariant : Color.mOnSurface))
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: {
            let usage = Math.round(SystemStatService.cpuUsage);
            if (usage < 100) {
              return `${usage}%`;
            } else {
              return usage;
            }
          }
          family: fontFamily
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when indicator active
          color: isVertical ? (cpuCritical ? criticalColor : (cpuWarning ? warningColor : textColor)) : ((cpuWarning || cpuCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.value = Qt.binding(() => SystemStatService.cpuUsage);
            item.warning = Qt.binding(() => cpuWarning);
            item.critical = Qt.binding(() => cpuCritical);
            item.warningColor = Qt.binding(() => root.warningColor);
            item.criticalColor = Qt.binding(() => root.criticalColor);
          }
        }
      }
    }

    // CPU Temperature Component
    Item {
      id: cpuTempContainer
      implicitWidth: cpuTempContent.implicitWidth
      implicitHeight: cpuTempContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showCpuTemp

      // Status indicator covering the entire component (only for non-compact mode)
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent
        visible: !compactMode

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
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "cpu-temperature"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // In compact mode, use threshold colors for icon; otherwise use existing logic
            color: compactMode ? (tempCritical ? criticalColor : (tempWarning ? warningColor : Color.mOnSurface)) : (isVertical ? (tempCritical ? criticalColor : (tempWarning ? warningColor : Color.mOnSurface)) : ((tempWarning || tempCritical) ? Color.mSurfaceVariant : Color.mOnSurface))
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: `${Math.round(SystemStatService.cpuTemp)}°`
          family: fontFamily
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when temp indicator active
          color: isVertical ? (tempCritical ? criticalColor : (tempWarning ? warningColor : textColor)) : ((tempWarning || tempCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }

        // Compact mode, mini gauge (to the right of icon)
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.value = Qt.binding(() => SystemStatService.cpuTemp);
            item.warning = Qt.binding(() => tempWarning);
            item.critical = Qt.binding(() => tempCritical);
            item.warningColor = Qt.binding(() => root.warningColor);
            item.criticalColor = Qt.binding(() => root.criticalColor);
          }
        }
      }
    }

    // GPU Temperature Component
    Item {
      id: gpuTempContainer
      implicitWidth: gpuTempContent.implicitWidth
      implicitHeight: gpuTempContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showGpuTemp && SystemStatService.gpuAvailable

      // Status indicator covering the entire component (only for non-compact mode)
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent
        visible: !compactMode

        onLoaded: {
          item.warning = Qt.binding(() => gpuWarning);
          item.critical = Qt.binding(() => gpuCritical);
          item.indicatorWidth = Qt.binding(() => gpuTempContainer.width);
          item.warningColor = Qt.binding(() => root.warningColor);
          item.criticalColor = Qt.binding(() => root.criticalColor);
        }
      }

      GridLayout {
        id: gpuTempContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "gpu-temperature"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // In compact mode, use threshold colors for icon; otherwise use existing logic
            color: compactMode ? (gpuCritical ? criticalColor : (gpuWarning ? warningColor : Color.mOnSurface)) : (isVertical ? (gpuCritical ? criticalColor : (gpuWarning ? warningColor : Color.mOnSurface)) : ((gpuWarning || gpuCritical) ? Color.mSurfaceVariant : Color.mOnSurface))
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: `${Math.round(SystemStatService.gpuTemp)}°`
          family: fontFamily
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when GPU temp indicator active
          color: isVertical ? (gpuCritical ? criticalColor : (gpuWarning ? warningColor : textColor)) : ((gpuWarning || gpuCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.value = Qt.binding(() => SystemStatService.gpuTemp);
            item.warning = Qt.binding(() => gpuWarning);
            item.critical = Qt.binding(() => gpuCritical);
            item.warningColor = Qt.binding(() => root.warningColor);
            item.criticalColor = Qt.binding(() => root.criticalColor);
          }
        }
      }
    }

    // Memory Usage Component
    Item {
      id: memoryContainer
      implicitWidth: memoryContent.implicitWidth
      implicitHeight: memoryContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showMemoryUsage

      // Status indicator covering the entire component (only for non-compact mode)
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent
        visible: !compactMode

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
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "memory"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // In compact mode, use threshold colors for icon; otherwise use existing logic
            color: compactMode ? (memCritical ? criticalColor : (memWarning ? warningColor : Color.mOnSurface)) : (isVertical ? (memCritical ? criticalColor : (memWarning ? warningColor : Color.mOnSurface)) : ((memWarning || memCritical) ? Color.mSurfaceVariant : Color.mOnSurface))
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: showMemoryAsPercent ? `${Math.round(SystemStatService.memPercent)}%` : SystemStatService.formatMemoryGb(SystemStatService.memGb)
          family: fontFamily
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when memory indicator active
          color: isVertical ? (memCritical ? criticalColor : (memWarning ? warningColor : textColor)) : ((memWarning || memCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.value = Qt.binding(() => SystemStatService.memPercent);
            item.warning = Qt.binding(() => memWarning);
            item.critical = Qt.binding(() => memCritical);
            item.warningColor = Qt.binding(() => root.warningColor);
            item.criticalColor = Qt.binding(() => root.criticalColor);
          }
        }
      }
    }

    // Network Download Speed Component
    Item {
      implicitWidth: downloadContent.implicitWidth
      implicitHeight: downloadContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: downloadContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
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

        // Text mode
        NText {
          visible: !compactMode
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.rxSpeed) : SystemStatService.formatSpeed(SystemStatService.rxSpeed)
          family: fontFamily
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.value = Qt.binding(() => getNetworkBarValue(SystemStatService.rxSpeed));
          }
        }
      }
    }

    // Network Upload Speed Component
    Item {
      implicitWidth: uploadContent.implicitWidth
      implicitHeight: uploadContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showNetworkStats

      GridLayout {
        id: uploadContent
        anchors.centerIn: parent
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
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

        // Text mode
        NText {
          visible: !compactMode
          text: isVertical ? SystemStatService.formatCompactSpeed(SystemStatService.txSpeed) : SystemStatService.formatSpeed(SystemStatService.txSpeed)
          family: fontFamily
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: textColor
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.value = Qt.binding(() => getNetworkBarValue(SystemStatService.txSpeed));
          }
        }
      }
    }

    // Disk Usage Component (primary drive)
    Item {
      id: diskContainer
      implicitWidth: diskContent.implicitWidth
      implicitHeight: diskContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showDiskUsage

      // Status indicator covering the entire component (only for non-compact mode)
      Loader {
        sourceComponent: statusIndicatorComponent
        anchors.centerIn: parent
        visible: !compactMode

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
        flow: (isVertical && !compactMode) ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: (isVertical && !compactMode) ? 2 : 1
        columns: (isVertical && !compactMode) ? 1 : 2
        rowSpacing: Style.marginXXS
        columnSpacing: compactMode ? 3 : Style.marginXS

        Item {
          Layout.alignment: Qt.AlignCenter
          Layout.row: (isVertical && !compactMode) ? 1 : 0
          Layout.column: 0
          Layout.fillWidth: isVertical
          implicitWidth: iconSize
          implicitHeight: iconSize

          NIcon {
            icon: "storage"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            // In compact mode, use threshold colors for icon; otherwise use existing logic
            color: compactMode ? (diskCritical ? criticalColor : (diskWarning ? warningColor : Color.mOnSurface)) : (isVertical ? (diskCritical ? criticalColor : (diskWarning ? warningColor : Color.mOnSurface)) : ((diskWarning || diskCritical) ? Color.mSurfaceVariant : Color.mOnSurface))
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: SystemStatService.diskPercents[diskPath] ? `${SystemStatService.diskPercents[diskPath]}%` : "n/a"
          family: fontFamily
          pointSize: textSize
          applyUiScale: false
          font.weight: Style.fontWeightMedium
          Layout.alignment: Qt.AlignCenter
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          // Use highlight colors in vertical bar; otherwise invert text color to bar background when disk indicator active
          color: isVertical ? (diskCritical ? criticalColor : (diskWarning ? warningColor : textColor)) : ((diskWarning || diskCritical) ? Color.mSurfaceVariant : textColor)
          Layout.row: isVertical ? 0 : 0
          Layout.column: isVertical ? 0 : 1
          scale: isVertical ? Math.min(1.0, root.width / implicitWidth) : 1.0
        }

        // Compact mode
        Loader {
          active: compactMode
          visible: compactMode
          sourceComponent: miniGaugeComponent
          Layout.alignment: Qt.AlignCenter
          Layout.row: 0
          Layout.column: 1

          onLoaded: {
            item.value = Qt.binding(() => SystemStatService.diskPercents[diskPath] ?? 0);
            item.warning = Qt.binding(() => diskWarning);
            item.critical = Qt.binding(() => diskCritical);
            item.warningColor = Qt.binding(() => root.warningColor);
            item.criticalColor = Qt.binding(() => root.criticalColor);
          }
        }
      }
    }
  }
}
