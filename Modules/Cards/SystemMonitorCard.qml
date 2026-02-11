import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Services.UI
import qs.Widgets

// Unified system card: monitors CPU, temp, memory, disk
NBox {
  id: root

  readonly property string diskPath: Settings.data.controlCenter.diskPath || "/"
  readonly property real contentScale: 0.95 * Style.uiScaleRatio

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginS

    Column {
      anchors.fill: parent

      Item {
        width: parent.width
        height: parent.height / 4

        NCircleStat {
          id: cpuUsageGauge
          anchors.centerIn: parent
          ratio: SystemStatService.cpuUsage / 100
          icon: "cpu-usage"
          contentScale: root.contentScale
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

      Item {
        width: parent.width
        height: parent.height / 4

        NCircleStat {
          id: cpuTempGauge
          anchors.centerIn: parent
          ratio: SystemStatService.cpuTemp / 100
          suffix: "°C"
          icon: "cpu-temperature"
          contentScale: root.contentScale
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

      Item {
        width: parent.width
        height: parent.height / 4

        NCircleStat {
          id: memPercentGauge
          anchors.centerIn: parent
          ratio: SystemStatService.memPercent / 100
          icon: "memory"
          contentScale: root.contentScale
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

      Item {
        width: parent.width
        height: parent.height / 4

        NCircleStat {
          id: diskPercentsGauge
          anchors.centerIn: parent
          ratio: (SystemStatService.diskPercents[root.diskPath] ?? 0) / 100
          icon: "storage"
          contentScale: root.contentScale
          fillColor: SystemStatService.getDiskColor(root.diskPath)
          tooltipText: I18n.tr("system-monitor.disk") + `: ${SystemStatService.diskPercents[root.diskPath] || 0}%\n${root.diskPath}`
        }

        Connections {
          target: SystemStatService
          function onDiskPercentsChanged() {
            if (TooltipService.activeTooltip && TooltipService.activeTooltip.targetItem === diskPercentsGauge) {
              TooltipService.updateText(I18n.tr("system-monitor.disk") + `: ${SystemStatService.diskPercents[root.diskPath] || 0}%\n${root.diskPath}`);
            }
          }
        }
      }
    }
  }
}
