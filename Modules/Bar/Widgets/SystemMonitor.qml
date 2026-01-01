import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
  property real barScaling: 1.0

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
  readonly property bool barCompact: Settings.data.bar.density === "compact"

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
  readonly property bool showLoadAverage: (widgetSettings.showLoadAverage !== undefined) ? widgetSettings.showLoadAverage : widgetMetadata.showLoadAverage
  readonly property string diskPath: (widgetSettings.diskPath !== undefined) ? widgetSettings.diskPath : widgetMetadata.diskPath
  readonly property string fontFamily: useMonospaceFont ? Settings.data.ui.fontFixed : Settings.data.ui.fontDefault

  readonly property real iconSize: Style.toOdd(Style.capsuleHeight * root.barScaling * (root.barCompact ? 0.55 : 0.45))
  readonly property real miniGaugeWidth: Math.max(3, Style.toOdd(root.iconSize * 0.25))
  readonly property real textSize: Math.max(7, iconSize * barScaling * 0.6 * (isVertical ? 0.85 : 1.0))

  function openExternalMonitor() {
    Quickshell.execDetached(["sh", "-c", Settings.data.systemMonitor.externalMonitor]);
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

    // Load Average
    if (SystemStatService.loadAvg1 >= 0) {
      lines.push(`${I18n.tr("system-monitor.load-average")}: ${SystemStatService.loadAvg1.toFixed(2)} ${SystemStatService.loadAvg5.toFixed(2)} ${SystemStatService.loadAvg15.toFixed(2)}`);
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

  readonly property color textColor: usePrimaryColor ? Color.mPrimary : Color.mOnSurface

  // Visibility-aware warning/critical states (delegates to service)
  readonly property bool cpuWarning: showCpuUsage && SystemStatService.cpuWarning
  readonly property bool cpuCritical: showCpuUsage && SystemStatService.cpuCritical
  readonly property bool tempWarning: showCpuTemp && SystemStatService.tempWarning
  readonly property bool tempCritical: showCpuTemp && SystemStatService.tempCritical
  readonly property bool gpuWarning: showGpuTemp && SystemStatService.gpuWarning
  readonly property bool gpuCritical: showGpuTemp && SystemStatService.gpuCritical
  readonly property bool memWarning: showMemoryUsage && SystemStatService.memWarning
  readonly property bool memCritical: showMemoryUsage && SystemStatService.memCritical
  readonly property bool diskWarning: showDiskUsage && SystemStatService.isDiskWarning(diskPath)
  readonly property bool diskCritical: showDiskUsage && SystemStatService.isDiskCritical(diskPath)

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
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    hoverEnabled: true
    onClicked: mouse => {
                 if (mouse.button === Qt.LeftButton) {
                   PanelService.getPanel("systemStatsPanel", screen)?.toggle(root);
                   TooltipService.hide();
                 } else if (mouse.button === Qt.RightButton) {
                   TooltipService.hide();
                   var popupMenuWindow = PanelService.getPopupMenuWindow(screen);
                   if (popupMenuWindow) {
                     popupMenuWindow.showContextMenu(contextMenu);
                     contextMenu.openAtItem(root, screen);
                   }
                 } else if (mouse.button === Qt.MiddleButton) {
                   TooltipService.hide();
                   openExternalMonitor();
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

  // Mini gauge component for compact mode, vertical gauge that fills from bottom
  Component {
    id: miniGaugeComponent

    Rectangle {
      id: miniGauge
      property real ratio: 0 // 0..1
      property color statColor: Color.mPrimary // Color based on warning/critical state

      width: miniGaugeWidth
      height: iconSize
      radius: width / 2
      color: Color.mOutline

      // Fill that grows from bottom
      Rectangle {
        property real fillHeight: parent.height * Math.min(1, Math.max(0, miniGauge.ratio))
        width: parent.width
        height: fillHeight
        radius: parent.radius
        color: miniGauge.statColor
        anchors.bottom: parent.bottom

        Behavior on fillHeight {
          enabled: !Settings.data.general.animationDisabled
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
            color: (cpuWarning || cpuCritical) ? SystemStatService.cpuColor : Color.mOnSurface
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
          color: (cpuWarning || cpuCritical) ? SystemStatService.cpuColor : textColor
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
            item.ratio = Qt.binding(() => SystemStatService.cpuUsage / 100);
            item.statColor = Qt.binding(() => SystemStatService.cpuColor);
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
            color: (tempWarning || tempCritical) ? SystemStatService.tempColor : Color.mOnSurface
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
          color: (tempWarning || tempCritical) ? SystemStatService.tempColor : textColor
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
            item.ratio = Qt.binding(() => SystemStatService.cpuTemp / 100);
            item.statColor = Qt.binding(() => SystemStatService.tempColor);
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
            color: (gpuWarning || gpuCritical) ? SystemStatService.gpuColor : Color.mOnSurface
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
          color: (gpuWarning || gpuCritical) ? SystemStatService.gpuColor : textColor
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
            item.ratio = Qt.binding(() => SystemStatService.gpuTemp / 100);
            item.statColor = Qt.binding(() => SystemStatService.gpuColor);
          }
        }
      }
    }

    // Load Average Component
    Item {
      id: loadAvgContainer
      implicitWidth: loadAvgContent.implicitWidth
      implicitHeight: loadAvgContent.implicitHeight
      Layout.preferredWidth: isVertical ? root.width : implicitWidth
      Layout.preferredHeight: compactMode ? implicitHeight : Style.capsuleHeight
      Layout.alignment: isVertical ? Qt.AlignHCenter : Qt.AlignVCenter
      visible: showLoadAverage && SystemStatService.nproc > 0 && SystemStatService.loadAvg1 > 0

      GridLayout {
        id: loadAvgContent
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
            icon: "weight"
            pointSize: iconSize
            applyUiScale: false
            anchors.centerIn: parent
            color: Color.mOnSurface
          }
        }

        // Text mode
        NText {
          visible: !compactMode
          text: SystemStatService.loadAvg1.toFixed(1)
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
            item.ratio = Qt.binding(() => Math.min(1, SystemStatService.loadAvg1 / SystemStatService.nproc));
            item.statColor = Qt.binding(() => Color.mPrimary);
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
            color: (memWarning || memCritical) ? SystemStatService.memColor : Color.mOnSurface
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
          color: (memWarning || memCritical) ? SystemStatService.memColor : textColor
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
            item.ratio = Qt.binding(() => SystemStatService.memPercent / 100);
            item.statColor = Qt.binding(() => SystemStatService.memColor);
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
            item.ratio = Qt.binding(() => SystemStatService.rxRatio);
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
            item.ratio = Qt.binding(() => SystemStatService.txRatio);
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
            color: (diskWarning || diskCritical) ? SystemStatService.getDiskColor(diskPath) : Color.mOnSurface
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
          color: (diskWarning || diskCritical) ? SystemStatService.getDiskColor(diskPath) : textColor
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
            item.ratio = Qt.binding(() => (SystemStatService.diskPercents[diskPath] ?? 0) / 100);
            item.statColor = Qt.binding(() => SystemStatService.getDiskColor(diskPath));
          }
        }
      }
    }
  }
}
