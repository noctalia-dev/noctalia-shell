import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

ColumnLayout {
  id: root

  spacing: Style.marginL

  NHeader {
    Layout.fillWidth: true
    label: I18n.tr("settings.system-monitor.general.section.label")
    description: I18n.tr("settings.system-monitor.general.section.description")
  }

  // Colors Section
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NToggle {
      label: I18n.tr("settings.system-monitor.use-custom-highlight-colors.label")
      description: I18n.tr("settings.system-monitor.use-custom-highlight-colors.description")
      checked: Settings.data.systemMonitor.useCustomColors
      onToggled: {
        // If enabling custom colors and no custom color is saved, persist current theme colors
        if (checked) {
          if (!Settings.data.systemMonitor.warningColor || Settings.data.systemMonitor.warningColor === "") {
            Settings.data.systemMonitor.warningColor = Color.mTertiary.toString();
          }
          if (!Settings.data.systemMonitor.criticalColor || Settings.data.systemMonitor.criticalColor === "") {
            Settings.data.systemMonitor.criticalColor = Color.mError.toString();
          }
        }
        Settings.data.systemMonitor.useCustomColors = checked;
      }
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: Settings.data.systemMonitor.useCustomColors

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.warning-color.label")
        pointSize: Style.fontSizeS
      }

      NColorPicker {
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        enabled: Settings.data.systemMonitor.useCustomColors
        selectedColor: Settings.data.systemMonitor.warningColor || Color.mTertiary
        onColorSelected: function (color) {
          Settings.data.systemMonitor.warningColor = color;
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        text: I18n.tr("settings.system-monitor.critical-color.label")
        pointSize: Style.fontSizeS
      }

      NColorPicker {
        Layout.preferredWidth: Style.sliderWidth
        Layout.preferredHeight: Style.baseWidgetSize
        enabled: Settings.data.systemMonitor.useCustomColors
        selectedColor: Settings.data.systemMonitor.criticalColor || Color.mError
        onColorSelected: function (color) {
          Settings.data.systemMonitor.criticalColor = color;
        }
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NHeader {
    Layout.fillWidth: true
    label: I18n.tr("settings.system-monitor.thresholds-section.label")
    description: I18n.tr("settings.system-monitor.thresholds-section.description")
  }

  // CPU Usage
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.cpu-section.label")
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
        text: I18n.tr("settings.system-monitor.cpu-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.cpuWarningThreshold
        onValueChanged: {
          Settings.data.systemMonitor.cpuWarningThreshold = value;
          // Ensure critical >= warning
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
        text: I18n.tr("settings.system-monitor.cpu-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.cpuWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.cpuCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.cpuCriticalThreshold = value
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("settings.system-monitor.polling-interval.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 250
        to: 10000
        stepSize: 250
        value: Settings.data.systemMonitor.cpuPollingInterval
        onValueChanged: Settings.data.systemMonitor.cpuPollingInterval = value
        suffix: " ms"
      }
    }
  }

  // Temperature
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.temperature-section.label")
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
        text: I18n.tr("settings.system-monitor.temp-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.tempWarningThreshold
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
        text: I18n.tr("settings.system-monitor.temp-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.tempWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.tempCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.tempCriticalThreshold = value
        suffix: "°C"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("settings.system-monitor.polling-interval.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 250
        to: 10000
        stepSize: 250
        value: Settings.data.systemMonitor.tempPollingInterval
        onValueChanged: Settings.data.systemMonitor.tempPollingInterval = value
        suffix: " ms"
      }
    }
  }

  // Memory Usage
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.memory-section.label")
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
        text: I18n.tr("settings.system-monitor.mem-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.memWarningThreshold
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
        text: I18n.tr("settings.system-monitor.mem-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.memWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.memCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.memCriticalThreshold = value
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("settings.system-monitor.polling-interval.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 250
        to: 10000
        stepSize: 250
        value: Settings.data.systemMonitor.memPollingInterval
        onValueChanged: Settings.data.systemMonitor.memPollingInterval = value
        suffix: " ms"
      }
    }
  }

  // Disk Usage
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.disk-section.label")
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
        text: I18n.tr("settings.system-monitor.disk-warning-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 0
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.diskWarningThreshold
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
        text: I18n.tr("settings.system-monitor.disk-critical-threshold.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: Settings.data.systemMonitor.diskWarningThreshold
        to: 100
        stepSize: 5
        value: Settings.data.systemMonitor.diskCriticalThreshold
        onValueChanged: Settings.data.systemMonitor.diskCriticalThreshold = value
        suffix: "%"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginM

      NText {
        Layout.alignment: Qt.AlignHCenter
        horizontalAlignment: Text.AlignHCenter
        text: I18n.tr("settings.system-monitor.polling-interval.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 250
        to: 10000
        stepSize: 250
        value: Settings.data.systemMonitor.diskPollingInterval
        onValueChanged: Settings.data.systemMonitor.diskPollingInterval = value
        suffix: " ms"
      }
    }
  }

  // Network
  NText {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    text: I18n.tr("settings.system-monitor.network-section.label")
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
        text: I18n.tr("settings.system-monitor.polling-interval.label")
        pointSize: Style.fontSizeS
      }

      NSpinBox {
        Layout.alignment: Qt.AlignHCenter
        from: 250
        to: 10000
        stepSize: 250
        value: Settings.data.systemMonitor.networkPollingInterval
        onValueChanged: Settings.data.systemMonitor.networkPollingInterval = value
        suffix: " ms"
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
