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

  NHeader {
    Layout.fillWidth: true
    label: I18n.tr("settings.system-monitor.polling-section.label")
    description: I18n.tr("settings.system-monitor.polling-section.description")
  }

  // CPU Polling
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginM

    NText {
      Layout.fillWidth: true
      text: I18n.tr("settings.system-monitor.cpu-section.label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.cpuPollingInterval
      isSettings: true
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
      text: I18n.tr("settings.system-monitor.temperature-section.label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.tempPollingInterval
      isSettings: true
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
      text: I18n.tr("settings.system-monitor.gpu-section.label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.gpuPollingInterval
      isSettings: true
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
      text: I18n.tr("settings.system-monitor.load-average-section.label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.loadAvgPollingInterval
      isSettings: true
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
      text: I18n.tr("settings.system-monitor.memory-section.label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.memPollingInterval
      isSettings: true
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
      text: I18n.tr("settings.system-monitor.disk-section.label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.diskPollingInterval
      isSettings: true
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
      text: I18n.tr("settings.system-monitor.network-section.label")
      pointSize: Style.fontSizeM
    }

    NSpinBox {
      from: 250
      to: 10000
      stepSize: 250
      value: Settings.data.systemMonitor.networkPollingInterval
      isSettings: true
      defaultValue: Settings.getDefaultValue("systemMonitor.networkPollingInterval")
      onValueChanged: Settings.data.systemMonitor.networkPollingInterval = value
      suffix: " ms"
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
  }

  NTextInput {
    label: I18n.tr("settings.system-monitor.external-monitor.label")
    description: I18n.tr("settings.system-monitor.external-monitor.description")
    placeholderText: I18n.tr("settings.system-monitor.external-monitor.placeholder")
    text: Settings.data.systemMonitor.externalMonitor
    isSettings: true
    defaultValue: Settings.getDefaultValue("systemMonitor.externalMonitor")
    onTextChanged: Settings.data.systemMonitor.externalMonitor = text
  }
}
