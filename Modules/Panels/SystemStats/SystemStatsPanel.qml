import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Modules.MainScreen
import qs.Services.System
import qs.Services.UI
import qs.Widgets

SmartPanel {
  id: root

  preferredWidth: Math.round(440 * Style.uiScaleRatio)
  preferredHeight: Math.round(420 * Style.uiScaleRatio)

  panelContent: Item {
    id: panelContent
    property real contentPreferredHeight: mainColumn.implicitHeight + Style.marginL * 2

    // Get diskPath from bar's SystemMonitor widget if available, otherwise use "/"
    readonly property string diskPath: {
      const sysMonWidget = BarService.lookupWidget("SystemMonitor");
      if (sysMonWidget && sysMonWidget.diskPath) {
        return sysMonWidget.diskPath;
      }
      return "/";
    }

    ColumnLayout {
      id: mainColumn
      anchors.fill: parent
      anchors.margins: Style.marginL
      spacing: Style.marginM

      // HEADER
      NBox {
        Layout.fillWidth: true
        implicitHeight: headerRow.implicitHeight + (Style.marginXL)

        RowLayout {
          id: headerRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          NIcon {
            icon: "device-analytics"
            pointSize: Style.fontSizeXXL
            color: Color.mPrimary
          }

          NText {
            text: I18n.tr("system-monitor.title")
            pointSize: Style.fontSizeL
            font.weight: Style.fontWeightBold
            color: Color.mOnSurface
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "close"
            tooltipText: I18n.tr("common.close")
            baseSize: Style.baseWidgetSize * 0.8
            onClicked: {
              root.close();
            }
          }
        }
      }

      // Stats Grid + Bottom section
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: statsContainer.implicitHeight + (Style.marginXL)

        ColumnLayout {
          id: statsContainer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.marginM
          spacing: Style.marginM

          // Top row: 5 NCircleStat gauges
          RowLayout {
            id: topRow
            Layout.fillWidth: true
            spacing: Style.marginS

            // CPU Usage
            Item {
              Layout.fillWidth: true
              implicitHeight: cpuUsageGauge.implicitHeight

              NCircleStat {
                id: cpuUsageGauge
                anchors.centerIn: parent
                ratio: SystemStatService.cpuUsage / 100
                icon: "cpu-usage"
                suffix: "%"
                fillColor: SystemStatService.cpuColor
                tooltipText: I18n.tr("system-monitor.cpu-usage") + `: ${Math.round(SystemStatService.cpuUsage)}%`
              }

              Connections {
                target: SystemStatService
                function onCpuUsageChanged() {
                  if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === cpuUsageGauge) {
                    TooltipService.updateText(I18n.tr("system-monitor.cpu-usage") + `: ${Math.round(SystemStatService.cpuUsage)}%`);
                  }
                }
              }
            }

            // CPU Temperature
            Item {
              Layout.fillWidth: true
              implicitHeight: cpuTempGauge.implicitHeight

              NCircleStat {
                id: cpuTempGauge
                anchors.centerIn: parent
                ratio: SystemStatService.cpuTemp / 100
                icon: "cpu-temperature"
                suffix: "\u00B0"
                fillColor: SystemStatService.tempColor
                tooltipText: I18n.tr("system-monitor.cpu-temp") + `: ${Math.round(SystemStatService.cpuTemp)}°C`
              }

              Connections {
                target: SystemStatService
                function onCpuTempChanged() {
                  if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === cpuTempGauge) {
                    TooltipService.updateText(I18n.tr("system-monitor.cpu-temp") + `: ${Math.round(SystemStatService.cpuTemp)}°C`);
                  }
                }
              }
            }

            // GPU Temperature
            Item {
              Layout.fillWidth: true
              implicitHeight: gpuTempGauge.implicitHeight
              visible: SystemStatService.gpuAvailable

              NCircleStat {
                id: gpuTempGauge
                anchors.centerIn: parent
                ratio: SystemStatService.gpuTemp / 100
                icon: "gpu-temperature"
                suffix: "\u00B0"
                fillColor: SystemStatService.gpuColor
                tooltipText: I18n.tr("system-monitor.gpu-temp") + `: ${Math.round(SystemStatService.gpuTemp)}°C`
              }

              Connections {
                target: SystemStatService
                function onGpuTempChanged() {
                  if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === gpuTempGauge) {
                    TooltipService.updateText(I18n.tr("system-monitor.gpu-temp") + `: ${Math.round(SystemStatService.gpuTemp)}°C`);
                  }
                }
              }
            }

            // Memory Usage
            Item {
              Layout.fillWidth: true
              implicitHeight: memPercentGauge.implicitHeight

              NCircleStat {
                id: memPercentGauge
                anchors.centerIn: parent
                ratio: SystemStatService.memPercent / 100
                icon: "memory"
                suffix: "%"
                fillColor: SystemStatService.memColor
                tooltipText: I18n.tr("common.memory") + `: ${Math.round(SystemStatService.memPercent)}%`
              }

              Connections {
                target: SystemStatService
                function onMemPercentChanged() {
                  if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === memPercentGauge) {
                    TooltipService.updateText(I18n.tr("common.memory") + `: ${Math.round(SystemStatService.memPercent)}%`);
                  }
                }
              }
            }

            // Swap Usage (only visible if swap is enabled)
            Item {
              Layout.fillWidth: true
              implicitHeight: swapPercentGauge.implicitHeight
              visible: SystemStatService.swapTotalGb > 0

              NCircleStat {
                id: swapPercentGauge
                anchors.centerIn: parent
                ratio: SystemStatService.swapPercent / 100
                icon: "exchange"
                suffix: "%"
                fillColor: SystemStatService.swapColor
                tooltipText: I18n.tr("bar.system-monitor.swap-usage-label") + `: ${Math.round(SystemStatService.swapPercent)}%`
              }

              Connections {
                target: SystemStatService
                function onSwapPercentChanged() {
                  if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === swapPercentGauge) {
                    TooltipService.updateText(I18n.tr("bar.system-monitor.swap-usage-label") + `: ${Math.round(SystemStatService.swapPercent)}%`);
                  }
                }
              }
            }

            // Disk Usage
            Item {
              Layout.fillWidth: true
              implicitHeight: diskPercentsGauge.implicitHeight

              NCircleStat {
                id: diskPercentsGauge
                anchors.centerIn: parent
                ratio: (SystemStatService.diskPercents[panelContent.diskPath] ?? 0) / 100
                icon: "storage"
                suffix: "%"
                fillColor: SystemStatService.getDiskColor(panelContent.diskPath)
                tooltipText: I18n.tr("system-monitor.disk") + `: ${SystemStatService.diskPercents[panelContent.diskPath] || 0}%\n${panelContent.diskPath}`
              }

              Connections {
                target: SystemStatService
                function onDiskPercentsChanged() {
                  if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === diskPercentsGauge) {
                    TooltipService.updateText(I18n.tr("system-monitor.disk") + `: ${SystemStatService.diskPercents[panelContent.diskPath] || 0}%\n${panelContent.diskPath}`);
                  }
                }
              }
            }
          }

          // Divider
          NDivider {
            Layout.fillWidth: true
            Layout.topMargin: Style.marginS
            Layout.bottomMargin: Style.marginXS
          }

          // Bottom row: 2 NCircleStat (download/upload) with speeds below + Detailed Stats
          RowLayout {
            id: bottomRow
            Layout.fillWidth: true
            spacing: Style.marginS

            // Number of visible gauges in top row
            readonly property int topRowGaugeCount: {
              let count = 4; // CPU, CPU Temp, Memory, Disk
              if (SystemStatService.gpuAvailable)
                count++;
              if (SystemStatService.swapTotalGb > 0)
                count++;
              return count;
            }

            // Download gauge with speed below (same width as top row items)
            Item {
              Layout.fillWidth: true
              implicitHeight: downloadColumn.implicitHeight

              ColumnLayout {
                id: downloadColumn
                anchors.centerIn: parent
                spacing: Style.marginS

                NCircleStat {
                  id: rxSpeedGauge
                  ratio: SystemStatService.rxRatio
                  icon: "download-speed"
                  suffix: "%"
                  fillColor: Color.mPrimary
                  tooltipText: I18n.tr("common.download") + `: ${SystemStatService.formatSpeed(SystemStatService.rxSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2")}` + "/s"
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: SystemStatService.formatSpeed(SystemStatService.rxSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2") + "/s"
                  pointSize: Style.fontSizeXXS
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                Connections {
                  target: SystemStatService
                  function onRxSpeedChanged() {
                    if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === rxSpeedGauge) {
                      TooltipService.updateText(I18n.tr("common.download") + `: ${SystemStatService.formatSpeed(SystemStatService.rxSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2")}` + "/s");
                    }
                  }
                }
              }
            }

            // Upload gauge with speed below (same width as top row items)
            Item {
              Layout.fillWidth: true
              implicitHeight: uploadColumn.implicitHeight

              ColumnLayout {
                id: uploadColumn
                anchors.centerIn: parent
                spacing: Style.marginS

                NCircleStat {
                  id: txSpeedGauge
                  ratio: SystemStatService.txRatio
                  icon: "upload-speed"
                  suffix: "%"
                  fillColor: Color.mPrimary
                  tooltipText: I18n.tr("common.upload") + `: ${SystemStatService.formatSpeed(SystemStatService.txSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2")}` + "/s"
                  Layout.alignment: Qt.AlignHCenter
                }

                NText {
                  text: SystemStatService.formatSpeed(SystemStatService.txSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2") + "/s"
                  pointSize: Style.fontSizeXXS
                  color: Color.mOnSurfaceVariant
                  Layout.alignment: Qt.AlignHCenter
                }

                Connections {
                  target: SystemStatService
                  function onTxSpeedChanged() {
                    if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === txSpeedGauge) {
                      TooltipService.updateText(I18n.tr("common.upload") + `: ${SystemStatService.formatSpeed(SystemStatService.txSpeed).replace(/([0-9.]+)([A-Za-z]+)/, "$1 $2")}` + "/s");
                    }
                  }
                }
              }
            }

            // Detailed Stats column (takes remaining space equivalent to topRowGaugeCount - 2 items)
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.preferredWidth: bottomRow.topRowGaugeCount - 2 // Match remaining top row slots

              ColumnLayout {
                id: detailsColumn
                anchors.fill: parent
                spacing: -Style.marginM

                // Load average
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS
                  visible: SystemStatService.nproc > 0

                  NIcon {
                    icon: "cpu-usage"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: I18n.tr("system-monitor.load-average") + ":"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: `${SystemStatService.loadAvg1.toFixed(2)} · ${SystemStatService.loadAvg5.toFixed(2)} · ${SystemStatService.loadAvg15.toFixed(2)}`
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                  }
                }

                // Memory details
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NIcon {
                    icon: "memory"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: I18n.tr("common.memory") + ":"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: SystemStatService.formatMemoryGb(SystemStatService.memGb).replace(/[^0-9.]/g, "") + " GB"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                  }
                }

                // Swap details (only visible if swap is enabled)
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS
                  visible: SystemStatService.swapTotalGb > 0

                  NIcon {
                    icon: "exchange"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: I18n.tr("bar.system-monitor.swap-usage-label") + ":"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: `${SystemStatService.formatMemoryGb(SystemStatService.swapGb).replace(/[^0-9.]/g, "") + " GB"} / ${SystemStatService.formatMemoryGb(SystemStatService.swapTotalGb).replace(/[^0-9.]/g, "") + " GB"}`
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                  }
                }

                // Disk details
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.marginS

                  NIcon {
                    icon: "storage"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: I18n.tr("system-monitor.disk") + ":"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurfaceVariant
                  }

                  NText {
                    text: {
                      const usedGb = SystemStatService.diskUsedGb[panelContent.diskPath] || 0;
                      const sizeGb = SystemStatService.diskSizeGb[panelContent.diskPath] || 0;
                      return `${usedGb.toFixed(1)} GB / ${sizeGb.toFixed(1)} GB`;
                    }
                    pointSize: Style.fontSizeXS
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
