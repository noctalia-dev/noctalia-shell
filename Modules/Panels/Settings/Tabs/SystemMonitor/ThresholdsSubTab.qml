import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  // CPU Usage
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("bar.system-monitor.cpu-usage-label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-warning")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.cpuWarningThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.cpuWarningThreshold")
        onValueChanged: {
          Settings.data.systemMonitor.cpuWarningThreshold = value;
          if (Settings.data.systemMonitor.cpuCriticalThreshold < value) {
            Settings.data.systemMonitor.cpuCriticalThreshold = value;
          }
        }
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-critical")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.cpuWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.cpuCriticalThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.cpuCriticalThreshold")
        onValueChanged: Settings.data.systemMonitor.cpuCriticalThreshold = value
        suffix: "%"
      }
    }
  }

  // Temperature
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("bar.system-monitor.cpu-temperature-label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-warning")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.tempWarningThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.tempWarningThreshold")
        onValueChanged: {
          Settings.data.systemMonitor.tempWarningThreshold = value;
          if (Settings.data.systemMonitor.tempCriticalThreshold < value) {
            Settings.data.systemMonitor.tempCriticalThreshold = value;
          }
        }
        suffix: "°C"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-critical")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.tempWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.tempCriticalThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.tempCriticalThreshold")
        onValueChanged: Settings.data.systemMonitor.tempCriticalThreshold = value
        suffix: "°C"
      }
    }
  }

  // GPU Temperature
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("panels.system-monitor.gpu-section-label")
    pointSize: Style.fontSizeM
    visible: SystemStatService.gpuAvailable
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: SystemStatService.gpuAvailable

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-warning")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 120
        stepSize: 5
        value: Settings.data.systemMonitor.gpuWarningThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.gpuWarningThreshold")
        onValueChanged: {
          Settings.data.systemMonitor.gpuWarningThreshold = value;
          if (Settings.data.systemMonitor.gpuCriticalThreshold < value) {
            Settings.data.systemMonitor.gpuCriticalThreshold = value;
          }
        }
        suffix: "°C"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-critical")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.gpuWarningThreshold
        to: 120
        stepSize: 5
        value: Settings.data.systemMonitor.gpuCriticalThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.gpuCriticalThreshold")
        onValueChanged: Settings.data.systemMonitor.gpuCriticalThreshold = value
        suffix: "°C"
      }
    }
  }

  // Memory Usage
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("bar.system-monitor.memory-usage-label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-warning")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.memWarningThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.memWarningThreshold")
        onValueChanged: {
          Settings.data.systemMonitor.memWarningThreshold = value;
          if (Settings.data.systemMonitor.memCriticalThreshold < value) {
            Settings.data.systemMonitor.memCriticalThreshold = value;
          }
        }
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-critical")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.memWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.memCriticalThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.memCriticalThreshold")
        onValueChanged: Settings.data.systemMonitor.memCriticalThreshold = value
        suffix: "%"
      }
    }
  }

  // Disk Usage
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("panels.system-monitor.disk-section-label")
    pointSize: Style.fontSizeM
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-warning")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.diskWarningThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.diskWarningThreshold")
        onValueChanged: {
          Settings.data.systemMonitor.diskWarningThreshold = value;
          if (Settings.data.systemMonitor.diskCriticalThreshold < value) {
            Settings.data.systemMonitor.diskCriticalThreshold = value;
          }
        }
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("panels.system-monitor.threshold-critical")
        pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.diskWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.diskCriticalThreshold
        defaultValue: Settings.getDefaultValue("systemMonitor.diskCriticalThreshold")
        onValueChanged: Settings.data.systemMonitor.diskCriticalThreshold = value
        suffix: "%"
      }
    }
  }
  NLabel {
    Layout.fillWidth: true
    description: I18n.tr("panels.system-monitor.thresholds-section-description")
  }
}
