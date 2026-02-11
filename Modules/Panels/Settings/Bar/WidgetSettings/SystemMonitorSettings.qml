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
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor
  property bool valueUseMonospaceFont: widgetData.useMonospaceFont !== undefined ? widgetData.useMonospaceFont : widgetMetadata.useMonospaceFont
  property bool valueShowCpuUsage: widgetData.showCpuUsage !== undefined ? widgetData.showCpuUsage : widgetMetadata.showCpuUsage
  property bool valueShowCpuFreq: widgetData.showCpuFreq !== undefined ? widgetData.showCpuFreq : widgetMetadata.showCpuFreq
  property bool valueShowCpuTemp: widgetData.showCpuTemp !== undefined ? widgetData.showCpuTemp : widgetMetadata.showCpuTemp
  property bool valueShowGpuTemp: widgetData.showGpuTemp !== undefined ? widgetData.showGpuTemp : widgetMetadata.showGpuTemp
  property bool valueShowLoadAverage: widgetData.showLoadAverage !== undefined ? widgetData.showLoadAverage : widgetMetadata.showLoadAverage
  property bool valueShowMemoryUsage: widgetData.showMemoryUsage !== undefined ? widgetData.showMemoryUsage : widgetMetadata.showMemoryUsage
  property bool valueShowMemoryAsPercent: widgetData.showMemoryAsPercent !== undefined ? widgetData.showMemoryAsPercent : widgetMetadata.showMemoryAsPercent
  property bool valueShowSwapUsage: widgetData.showSwapUsage !== undefined ? widgetData.showSwapUsage : widgetMetadata.showSwapUsage
  property bool valueShowNetworkStats: widgetData.showNetworkStats !== undefined ? widgetData.showNetworkStats : widgetMetadata.showNetworkStats
  property bool valueShowDiskUsage: widgetData.showDiskUsage !== undefined ? widgetData.showDiskUsage : widgetMetadata.showDiskUsage
  property bool valueShowDiskUsageAsPercent: widgetData.showDiskUsageAsPercent !== undefined ? widgetData.showDiskUsageAsPercent : widgetMetadata.showDiskUsageAsPercent
  property bool valueShowDiskAvailable: widgetData.showDiskAvailable !== undefined ? widgetData.showDiskAvailable : widgetMetadata.showDiskAvailable
  property string valueDiskPath: widgetData.diskPath !== undefined ? widgetData.diskPath : widgetMetadata.diskPath

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.compactMode = valueCompactMode;
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    settings.useMonospaceFont = valueUseMonospaceFont;
    settings.showCpuUsage = valueShowCpuUsage;
    settings.showCpuFreq = valueShowCpuFreq;
    settings.showCpuTemp = valueShowCpuTemp;
    settings.showGpuTemp = valueShowGpuTemp;
    settings.showLoadAverage = valueShowLoadAverage;
    settings.showMemoryUsage = valueShowMemoryUsage;
    settings.showMemoryAsPercent = valueShowMemoryAsPercent;
    settings.showSwapUsage = valueShowSwapUsage;
    settings.showNetworkStats = valueShowNetworkStats;
    settings.showDiskUsage = valueShowDiskUsage;
    settings.showDiskUsageAsPercent = valueShowDiskUsageAsPercent;
    settings.showDiskAvailable = valueShowDiskAvailable;
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

  NComboBox {
    label: I18n.tr("common.select-icon-color")
    description: I18n.tr("common.select-color-description")
    model: Color.colorKeyModel
    currentKey: valueIconColor
    onSelected: key => {
                  valueIconColor = key;
                  settingsChanged(saveSettings());
                }
    minimumWidth: 200
  }

  NComboBox {
    label: I18n.tr("common.select-color")
    description: I18n.tr("common.select-color-description")
    model: Color.colorKeyModel
    currentKey: valueTextColor
    onSelected: key => {
                  valueTextColor = key;
                  settingsChanged(saveSettings());
                }
    minimumWidth: 200
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
    id: showCpuFreq
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.cpu-frequency-label")
    description: I18n.tr("bar.system-monitor.cpu-frequency-description")
    checked: valueShowCpuFreq
    onToggled: checked => {
                 valueShowCpuFreq = checked;
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

  NToggle {
    id: showDiskUsageAsPercent
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.storage-as-percentage-label")
    description: I18n.tr("bar.system-monitor.storage-as-percentage-description")
    checked: valueShowDiskUsageAsPercent
    onToggled: checked => {
                 valueShowDiskUsageAsPercent = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    id: showDiskAvailable
    Layout.fillWidth: true
    label: I18n.tr("bar.system-monitor.storage-available-label")
    description: I18n.tr("bar.system-monitor.storage-available-description")
    checked: valueShowDiskAvailable
    onToggled: checked => {
                 valueShowDiskAvailable = checked;
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
