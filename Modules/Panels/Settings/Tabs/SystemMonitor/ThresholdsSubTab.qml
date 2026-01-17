import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  Layout.fillWidth: true

  NLabel {
    Layout.fillWidth: true
    description: I18n.tr("panels.system-monitor.thresholds-section-description")
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    columns: 3
    columnSpacing: Style.marginM
    rowSpacing: Style.marginM

    // Header row
    Item { Layout.fillWidth: true }

    NText {
      Layout.alignment: Qt.AlignHCenter
      horizontalAlignment: Text.AlignHCenter
      text: I18n.tr("panels.system-monitor.threshold-warning")
      pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
    }

    NText {
      Layout.alignment: Qt.AlignHCenter
      horizontalAlignment: Text.AlignHCenter
      text: I18n.tr("panels.system-monitor.threshold-critical")
      pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
    }

    // CPU Usage
    NText {
      text: I18n.tr("bar.system-monitor.cpu-usage-label")
      pointSize: Style.fontSizeL
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: 0
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.cpuWarningThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.cpuWarningThreshold")
      suffix: "%"
      onValueChanged: {
        Settings.data.systemMonitor.cpuWarningThreshold = value;
        if (Settings.data.systemMonitor.cpuCriticalThreshold < value) {
          Settings.data.systemMonitor.cpuCriticalThreshold = value;
        }
      }
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: Settings.data.systemMonitor.cpuWarningThreshold
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.cpuCriticalThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.cpuCriticalThreshold")
      suffix: "%"
      onValueChanged: Settings.data.systemMonitor.cpuCriticalThreshold = value
    }

    // CPU Temperature
    NText {
      text: I18n.tr("bar.system-monitor.cpu-temperature-label")
      pointSize: Style.fontSizeL
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: 0
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.tempWarningThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.tempWarningThreshold")
      suffix: "°C"
      onValueChanged: {
        Settings.data.systemMonitor.tempWarningThreshold = value;
        if (Settings.data.systemMonitor.tempCriticalThreshold < value) {
          Settings.data.systemMonitor.tempCriticalThreshold = value;
        }
      }
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: Settings.data.systemMonitor.tempWarningThreshold
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.tempCriticalThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.tempCriticalThreshold")
      suffix: "°C"
      onValueChanged: Settings.data.systemMonitor.tempCriticalThreshold = value
    }

    // GPU Temperature
    NText {
      visible: SystemStatService.gpuAvailable
      text: I18n.tr("panels.system-monitor.gpu-section-label")
      pointSize: Style.fontSizeL
    }

    NSpinBox {
      visible: SystemStatService.gpuAvailable
      Layout.alignment: Qt.AlignHCenter
      from: 0
      to: 120
      stepSize: 5
      value: Settings.data.systemMonitor.gpuWarningThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.gpuWarningThreshold")
      suffix: "°C"
      onValueChanged: {
        Settings.data.systemMonitor.gpuWarningThreshold = value;
        if (Settings.data.systemMonitor.gpuCriticalThreshold < value) {
          Settings.data.systemMonitor.gpuCriticalThreshold = value;
        }
      }
    }

    NSpinBox {
      visible: SystemStatService.gpuAvailable
      Layout.alignment: Qt.AlignHCenter
      from: Settings.data.systemMonitor.gpuWarningThreshold
      to: 120
      stepSize: 5
      value: Settings.data.systemMonitor.gpuCriticalThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.gpuCriticalThreshold")
      suffix: "°C"
      onValueChanged: Settings.data.systemMonitor.gpuCriticalThreshold = value
    }

    // Memory Usage
    NText {
      text: I18n.tr("bar.system-monitor.memory-usage-label")
      pointSize: Style.fontSizeL
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: 0
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.memWarningThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.memWarningThreshold")
      suffix: "%"
      onValueChanged: {
        Settings.data.systemMonitor.memWarningThreshold = value;
        if (Settings.data.systemMonitor.memCriticalThreshold < value) {
          Settings.data.systemMonitor.memCriticalThreshold = value;
        }
      }
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: Settings.data.systemMonitor.memWarningThreshold
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.memCriticalThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.memCriticalThreshold")
      suffix: "%"
      onValueChanged: Settings.data.systemMonitor.memCriticalThreshold = value
    }

    // Disk Usage
    NText {
      text: I18n.tr("panels.system-monitor.disk-section-label")
      pointSize: Style.fontSizeL
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: 0
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.diskWarningThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.diskWarningThreshold")
      suffix: "%"
      onValueChanged: {
        Settings.data.systemMonitor.diskWarningThreshold = value;
        if (Settings.data.systemMonitor.diskCriticalThreshold < value) {
          Settings.data.systemMonitor.diskCriticalThreshold = value;
        }
      }
    }

    NSpinBox {
      Layout.alignment: Qt.AlignHCenter
      from: Settings.data.systemMonitor.diskWarningThreshold
      to: 100
      stepSize: 5
      value: Settings.data.systemMonitor.diskCriticalThreshold
      defaultValue: Settings.getDefaultValue("systemMonitor.diskCriticalThreshold")
      suffix: "%"
      onValueChanged: Settings.data.systemMonitor.diskCriticalThreshold = value
    }
  }

}
