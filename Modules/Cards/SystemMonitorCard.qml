import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.System
import qs.Widgets

// Unified system card: monitors CPU, temp, memory, disk
NBox {
  id: root

  Item {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginS

    property int widgetHeight: Math.round(65 * Style.uiScaleRatio)

    ColumnLayout {
      anchors.centerIn: parent
      spacing: 0

      NCircleStat {
        value: SystemStatService.cpuUsage
        icon: "cpu-usage"
        flat: true
        contentScale: 0.8
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        // Highlight color based on thresholds
        fillColor: (SystemStatService.cpuUsage > Settings.data.systemMonitor.cpuCriticalThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.criticalColor || Color.mError) : Color.mError) : (SystemStatService.cpuUsage > Settings.data.systemMonitor.cpuWarningThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (
                                                                                                                                                                                                                                                                                                                                                                    Settings.data.systemMonitor.warningColor
                                                                                                                                                                                                                                                                                                                                                                    || Color.mTertiary) :
                                                                                                                                                                                                                                                                                                                                                                  Color.mTertiary) :
                                                                                                                                                                                                                                                                                                                   Color.mPrimary
        textColor: (SystemStatService.cpuUsage > Settings.data.systemMonitor.cpuCriticalThreshold) ? Color.mSurfaceVariant : (SystemStatService.cpuUsage > Settings.data.systemMonitor.cpuWarningThreshold) ? Color.mSurfaceVariant : Color.mOnSurface
      }
      NCircleStat {
        value: SystemStatService.cpuTemp
        suffix: "°C"
        icon: "cpu-temperature"
        flat: true
        contentScale: 0.8
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        // Highlight color based on thresholds
        fillColor: (SystemStatService.cpuTemp > Settings.data.systemMonitor.tempCriticalThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.criticalColor || Color.mError) : Color.mError) : (SystemStatService.cpuTemp > Settings.data.systemMonitor.tempWarningThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (
                                                                                                                                                                                                                                                                                                                                                                    Settings.data.systemMonitor.warningColor
                                                                                                                                                                                                                                                                                                                                                                    || Color.mTertiary) :
                                                                                                                                                                                                                                                                                                                                                                  Color.mTertiary) :
                                                                                                                                                                                                                                                                                                                   Color.mPrimary
        textColor: (SystemStatService.cpuTemp > Settings.data.systemMonitor.tempCriticalThreshold) ? Color.mSurfaceVariant : (SystemStatService.cpuTemp > Settings.data.systemMonitor.tempWarningThreshold) ? Color.mSurfaceVariant : Color.mOnSurface
      }
      NCircleStat {
        value: SystemStatService.memPercent
        icon: "memory"
        flat: true
        contentScale: 0.8
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        // Highlight color based on thresholds
        fillColor: (SystemStatService.memPercent > Settings.data.systemMonitor.memCriticalThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.criticalColor || Color.mError) : Color.mError) : (SystemStatService.memPercent > Settings.data.systemMonitor.memWarningThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (
                                                                                                                                                                                                                                                                                                                                                                        Settings.data.systemMonitor.warningColor
                                                                                                                                                                                                                                                                                                                                                                        || Color.mTertiary) :
                                                                                                                                                                                                                                                                                                                                                                      Color.mTertiary) :
                                                                                                                                                                                                                                                                                                                       Color.mPrimary
        textColor: (SystemStatService.memPercent > Settings.data.systemMonitor.memCriticalThreshold) ? Color.mSurfaceVariant : (SystemStatService.memPercent > Settings.data.systemMonitor.memWarningThreshold) ? Color.mSurfaceVariant : Color.mOnSurface
      }
      NCircleStat {
        readonly property string diskPath: Settings.data.systemMonitor.diskPath || "/"
        readonly property real diskPercent: SystemStatService.diskPercents[diskPath] ?? 0
        value: diskPercent
        icon: "storage"
        flat: true
        contentScale: 0.8
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
        // Highlight color based on thresholds
        fillColor: (diskPercent > Settings.data.systemMonitor.diskCriticalThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (Settings.data.systemMonitor.criticalColor || Color.mError) : Color.mError) : (diskPercent > Settings.data.systemMonitor.diskWarningThreshold) ? (Settings.data.systemMonitor.useCustomColors ? (
                                                                                                                                                                                                                                                                                                                                        Settings.data.systemMonitor.warningColor
                                                                                                                                                                                                                                                                                                                                        || Color.mTertiary) :
                                                                                                                                                                                                                                                                                                                                      Color.mTertiary) : Color.mPrimary
        textColor: (diskPercent > Settings.data.systemMonitor.diskCriticalThreshold) ? Color.mSurfaceVariant : (diskPercent > Settings.data.systemMonitor.diskWarningThreshold) ? Color.mSurfaceVariant : Color.mOnSurface
      }
    }
  }
}
