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

  NLabel {
    Layout.fillWidth: true
    description: I18n.tr("panels.system-monitor.polling-section-description")
  }
  // CPU Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: I18n.tr("bar.system-monitor.cpu-usage-label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.cpuPollingInterval
      defaultValue: Settings.getDefaultValue("systemMonitor.cpuPollingInterval")
      onValueChanged: Settings.data.systemMonitor.cpuPollingInterval = value
      suffix: " ms"
    }
  }

  // Temperature Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: I18n.tr("bar.system-monitor.cpu-temperature-label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.tempPollingInterval
      defaultValue: Settings.getDefaultValue("systemMonitor.tempPollingInterval")
      onValueChanged: Settings.data.systemMonitor.tempPollingInterval = value
      suffix: " ms"
    }
  }

  // GPU Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM
    visible: SystemStatService.gpuAvailable

    NText {
      Layout.fillWidth: true
      text: I18n.tr("panels.system-monitor.gpu-section-label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.gpuPollingInterval
      defaultValue: Settings.getDefaultValue("systemMonitor.gpuPollingInterval")
      onValueChanged: Settings.data.systemMonitor.gpuPollingInterval = value
      suffix: " ms"
    }
  }

  // Load Average Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: I18n.tr("bar.system-monitor.load-average-label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.loadAvgPollingInterval
      defaultValue: Settings.getDefaultValue("systemMonitor.loadAvgPollingInterval")
      onValueChanged: Settings.data.systemMonitor.loadAvgPollingInterval = value
      suffix: " ms"
    }
  }

  // Memory Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: I18n.tr("bar.system-monitor.memory-usage-label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.memPollingInterval
      defaultValue: Settings.getDefaultValue("systemMonitor.memPollingInterval")
      onValueChanged: Settings.data.systemMonitor.memPollingInterval = value
      suffix: " ms"
    }
  }

  // Disk Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: I18n.tr("panels.system-monitor.disk-section-label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.diskPollingInterval
      defaultValue: Settings.getDefaultValue("systemMonitor.diskPollingInterval")
      onValueChanged: Settings.data.systemMonitor.diskPollingInterval = value
      suffix: " ms"
    }
  }

  // Network Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: I18n.tr("common.network")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.networkPollingInterval
      defaultValue: Settings.getDefaultValue("systemMonitor.networkPollingInterval")
      onValueChanged: Settings.data.systemMonitor.networkPollingInterval = value
      suffix: " ms"
    }
  }
}
