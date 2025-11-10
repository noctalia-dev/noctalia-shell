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
      }
      NCircleStat {
        value: SystemStatService.cpuTemp
        suffix: "°C"
        icon: "cpu-temperature"
        flat: true
        contentScale: 0.8
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
      }
      NCircleStat {
        value: SystemStatService.memPercent
        icon: "memory"
        flat: true
        contentScale: 0.8
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
      }
      NCircleStat {
        value: SystemStatService.diskPercents["/"] ?? 0
        icon: "storage"
        flat: true
        contentScale: 0.8
        height: content.widgetHeight
        Layout.alignment: Qt.AlignHCenter
      }
    }
  }
}
