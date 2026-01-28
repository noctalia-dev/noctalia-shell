import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local, editable state for checkboxes
  property bool valueCompactMode: widgetData.compactMode !== undefined ? widgetData.compactMode : widgetMetadata.compactMode
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : widgetMetadata.usePrimaryColor
  property bool valueUseMonospaceFont: widgetData.useMonospaceFont !== undefined ? widgetData.useMonospaceFont : widgetMetadata.useMonospaceFont
  property bool valueShowCpuUsage: widgetData.showCpuUsage !== undefined ? widgetData.showCpuUsage : widgetMetadata.showCpuUsage
  property bool valueShowCpuTemp: widgetData.showCpuTemp !== undefined ? widgetData.showCpuTemp : widgetMetadata.showCpuTemp
  property bool valueShowGpuTemp: widgetData.showGpuTemp !== undefined ? widgetData.showGpuTemp : widgetMetadata.showGpuTemp
  property bool valueShowLoadAverage: widgetData.showLoadAverage !== undefined ? widgetData.showLoadAverage : widgetMetadata.showLoadAverage
  property bool valueShowMemoryUsage: widgetData.showMemoryUsage !== undefined ? widgetData.showMemoryUsage : widgetMetadata.showMemoryUsage
  property bool valueShowMemoryAsPercent: widgetData.showMemoryAsPercent !== undefined ? widgetData.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  property bool valueShowSwapUsage: widgetData.showSwapUsage !== undefined ? widgetData.showSwapUsage : widgetMetadata.showSwapUsage
  property bool valueShowNetworkStats: widgetData.showNetworkStats !== undefined ? widgetData.showNetworkStats : widgetMetadata.showNetworkStats
  property bool valueShowDiskUsage: widgetData.showDiskUsage !== undefined ? widgetData.showDiskUsage : widgetMetadata.showDiskUsage
  property string valueDiskPath: widgetData.diskPath !== undefined ? widgetData.diskPath : widgetMetadata.diskPath

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.compactMode = valueCompactMode;
    settings.usePrimaryColor = valueUsePrimaryColor;
    settings.useMonospaceFont = valueUseMonospaceFont;
    settings.showCpuUsage = valueShowCpuUsage;
    settings.showCpuTemp = valueShowCpuTemp;
    settings.showGpuTemp = valueShowGpuTemp;
    settings.showLoadAverage = valueShowLoadAverage;
    settings.showMemoryUsage = valueShowMemoryUsage;
    settings.showMemoryAsPercent = valueShowMemoryAsPercent;
    settings.showSwapUsage = valueShowSwapUsage;
    settings.showNetworkStats = valueShowNetworkStats;
    settings.showDiskUsage = valueShowDiskUsage;
    settings.diskPath = valueDiskPath;

    return settings;
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.compact-mode-label")
    description: I18n.tr("bar.system-monitor.compact-mode-description")
    checked: valueCompactMode
    onToggled: checked => {
                 valueCompactMode = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.clock.use-primary-color-label")
    description: I18n.tr("bar.clock.use-primary-color-description")
    checked: valueUsePrimaryColor
    onToggled: checked => {
                 valueUsePrimaryColor = checked;
                 settingsChanged(saveSettings());
               }
    visible: !valueCompactMode
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.use-monospace-font-label")
    description: I18n.tr("bar.system-monitor.use-monospace-font-description")
    checked: valueUseMonospaceFont
    onToggled: checked => {
                 valueUseMonospaceFont = checked;
                 settingsChanged(saveSettings());
               }
    visible: !valueCompactMode
  }

  NToggle {
    id: showCpuUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.cpu-usage-label")
    description: I18n.tr("bar.system-monitor.cpu-usage-description")
    checked: valueShowCpuUsage
    onToggled: checked => {
                 valueShowCpuUsage = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    id: showCpuTemp
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.cpu-temperature-label")
    description: I18n.tr("bar.system-monitor.cpu-temperature-description")
    checked: valueShowCpuTemp
    onToggled: checked => {
                 valueShowCpuTemp = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    id: showGpuTemp
    Layout.fillWidth: true
    label: I18n.tr("panels.system-monitor.gpu-section-label")
    description: I18n.tr("bar.system-monitor.gpu-temperature-description")
    checked: valueShowGpuTemp
    onToggled: checked => {
                 valueShowGpuTemp = checked;
                 settingsChanged(saveSettings());
               }
    visible: SystemStatService.gpuAvailable
  }

  NToggle {
    id: showLoadAverage
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.load-average-label")
    description: I18n.tr("bar.system-monitor.load-average-description")
    checked: valueShowLoadAverage
    onToggled: checked => {
                 valueShowLoadAverage = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    id: showMemoryUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.memory-usage-label")
    description: I18n.tr("bar.system-monitor.memory-usage-description")
    checked: valueShowMemoryUsage
    onToggled: checked => {
                 valueShowMemoryUsage = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    id: showMemoryAsPercent
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.memory-percentage-label")
    description: I18n.tr("bar.system-monitor.memory-percentage-description")
    checked: valueShowMemoryAsPercent
    onToggled: checked => {
                 valueShowMemoryAsPercent = checked;
                 settingsChanged(saveSettings());
               }
    visible: valueShowMemoryUsage
  }

  NToggle {
    id: showSwapUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.swap-usage-label")
    description: I18n.tr("bar.system-monitor.swap-usage-description")
    checked: valueShowSwapUsage
    onToggled: checked => {
                 valueShowSwapUsage = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    id: showNetworkStats
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.network-traffic-label")
    description: I18n.tr("bar.system-monitor.network-traffic-description")
    checked: valueShowNetworkStats
    onToggled: checked => {
                 valueShowNetworkStats = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    id: showDiskUsage
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.storage-usage-label")
    description: I18n.tr("bar.system-monitor.storage-usage-description")
    checked: valueShowDiskUsage
    onToggled: checked => {
                 valueShowDiskUsage = checked;
                 settingsChanged(saveSettings());
               }
  }

  NComboBox {
    id: diskPathComboBox
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.disk-path-label")
    description: I18n.tr("bar.system-monitor.disk-path-description")
    model: {
      const paths = Object.keys(SystemStatService.diskPercents).sort();
      return paths.map(path => ({
                                  key: path,
                                  name: path
                                }));
    }
    currentKey: valueDiskPath
    onSelected: key => {
                  valueDiskPath = key;
                  settingsChanged(saveSettings());
                }
  }
}
