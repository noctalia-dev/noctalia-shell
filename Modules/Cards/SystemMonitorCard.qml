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

  // Get diskPath from bar's SystemMonitor widget if available, otherwise use settings
  readonly property string diskPath: {
    const sysMonWidget = BarService.lookupWidget("SystemMonitor");
    if (sysMonWidget && sysMonWidget.diskPath) {
      return sysMonWidget.diskPath;
    }
    return Settings.data.systemMonitor.diskPath || "/";
  }

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginS

    property int widgetHeight: Math.round(65 * Style.uiScaleRatio)

    ColumnLayout {
      anchors.centerIn: parent
      spacing: Style.marginXS

      NCircleStat {
        ratio: SystemStatService.cpuUsage / 100
        icon: "cpu-usage"
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.cpuColor
        tooltipText: I18n.tr("system-monitor.cpu-usage") + `: ${Math.round(SystemStatService.cpuUsage)}%`
      }
      NCircleStat {
        ratio: SystemStatService.cpuTemp / 100
        suffix: "°C"
        icon: "cpu-temperature"
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.tempColor
        tooltipText: I18n.tr("system-monitor.cpu-temp") + `: ${Math.round(SystemStatService.cpuTemp)}°C`
      }
      NCircleStat {
        ratio: SystemStatService.memPercent / 100
        icon: "memory"
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.memColor
        tooltipText: I18n.tr("system-monitor.memory") + `: ${Math.round(SystemStatService.memPercent)}%`
      }
      NCircleStat {
        ratio: (SystemStatService.diskPercents[root.diskPath] ?? 0) / 100
        icon: "storage"
        contentScale: 0.95
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        fillColor: SystemStatService.getDiskColor(root.diskPath)
        tooltipText: I18n.tr("system-monitor.disk") + `: ${SystemStatService.diskPercents[root.diskPath] || 0}%\n${root.diskPath}`
      }
    }
  }
}
