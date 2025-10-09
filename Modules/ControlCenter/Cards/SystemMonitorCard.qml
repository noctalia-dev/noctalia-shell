import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Widgets

// Unified system card: monitors CPU, temp, memory, disk
NBox {
  id: root

  GridLayout {
    id: content
    anchors.fill: parent
    anchors.margins: Style.marginXS * scaling
    columns: 2
    rows: 2
    columnSpacing: Style.marginS * scaling
    rowSpacing: Style.marginS * scaling

    NCircleStat {
      value: SystemStatService.cpuUsage
      icon: "cpu-usage"
      flat: true
      contentScale: 0.8
      Layout.fillWidth: true
      Layout.fillHeight: true
    }
    NCircleStat {
      value: SystemStatService.cpuTemp
      suffix: "°C"
      icon: "cpu-temperature"
      flat: true
      contentScale: 0.8
      Layout.fillWidth: true
      Layout.fillHeight: true
    }
    NCircleStat {
      value: SystemStatService.memPercent
      icon: "memory"
      flat: true
      contentScale: 0.8
      Layout.fillWidth: true
      Layout.fillHeight: true
    }
    NCircleStat {
      value: SystemStatService.diskPercent
      icon: "storage"
      flat: true
      contentScale: 0.8
      Layout.fillWidth: true
      Layout.fillHeight: true
    }
  }
}
