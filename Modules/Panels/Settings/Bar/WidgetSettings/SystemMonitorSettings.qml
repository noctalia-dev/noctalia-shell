import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local, editable state for checkboxes
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool valueShowCpuUsage: widgetData.showCpuUsage !== undefined ? widgetData.showCpuUsage : widgetMetadata.showCpuUsage
  property bool valueShowCpuTemp: widgetData.showCpuTemp !== undefined ? widgetData.showCpuTemp : widgetMetadata.showCpuTemp
  property bool valueShowMemoryUsage: widgetData.showMemoryUsage !== undefined ? widgetData.showMemoryUsage : widgetMetadata.showMemoryUsage
  property bool valueShowMemoryAsPercent: widgetData.showMemoryAsPercent !== undefined ? widgetData.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  property bool valueShowNetworkStats: widgetData.showNetworkStats !== undefined ? widgetData.showNetworkStats : widgetMetadata.showNetworkStats
  property bool valueShowDiskUsage: widgetData.showDiskUsage !== undefined ? widgetData.showDiskUsage : widgetMetadata.showDiskUsage

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.usePrimaryColor = valueUsePrimaryColor
    settings.showCpuUsage = valueShowCpuUsage
    settings.showCpuTemp = valueShowCpuTemp
    settings.showMemoryUsage = valueShowMemoryUsage
    settings.showMemoryAsPercent = valueShowMemoryAsPercent
    settings.showNetworkStats = valueShowNetworkStats
    settings.showDiskUsage = valueShowDiskUsage
    return settings
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.clock.use-primary-color.label")
    description: I18n.tr("bar.widget-settings.clock.use-primary-color.description")
    checked: valueUsePrimaryColor
    onToggled: checked => valueUsePrimaryColor = checked
  }

  NToggle {
    id: showCpuUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.cpu-usage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.cpu-usage.description")
    checked: valueShowCpuUsage
    onToggled: checked => valueShowCpuUsage = checked
  }

  NToggle {
    id: showCpuTemp
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.cpu-temperature.label")
    description: I18n.tr("bar.widget-settings.system-monitor.cpu-temperature.description")
    checked: valueShowCpuTemp
    onToggled: checked => valueShowCpuTemp = checked
  }

  NToggle {
    id: showMemoryUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.memory-usage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.memory-usage.description")
    checked: valueShowMemoryUsage
    onToggled: checked => valueShowMemoryUsage = checked
  }

  NToggle {
    id: showMemoryAsPercent
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.memory-percentage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.memory-percentage.description")
    checked: valueShowMemoryAsPercent
    onToggled: checked => valueShowMemoryAsPercent = checked
    visible: valueShowMemoryUsage
  }

  NToggle {
    id: showNetworkStats
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.network-traffic.label")
    description: I18n.tr("bar.widget-settings.system-monitor.network-traffic.description")
    checked: valueShowNetworkStats
    onToggled: checked => valueShowNetworkStats = checked
  }

  NToggle {
    id: showDiskUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.system-monitor.storage-usage.label")
    description: I18n.tr("bar.widget-settings.system-monitor.storage-usage.description")
    checked: valueShowDiskUsage
    onToggled: checked => valueShowDiskUsage = checked
  }
}
