import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  width: 700

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property string valueStatType: widgetData.statType !== undefined ? widgetData.statType : widgetMetadata.statType
  property string valueDiskPath: widgetData.diskPath !== undefined ? widgetData.diskPath : widgetMetadata.diskPath
  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : widgetMetadata.showBackground
  property bool valueRoundedCorners: widgetData.roundedCorners !== undefined ? widgetData.roundedCorners : (widgetMetadata.roundedCorners !== undefined ? widgetMetadata.roundedCorners : true)
  property string valueLayout: widgetData.layout !== undefined ? widgetData.layout : (widgetMetadata.layout !== undefined ? widgetMetadata.layout : "side")

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.statType = valueStatType;
    settings.diskPath = valueDiskPath;
    settings.showBackground = valueShowBackground;
    settings.roundedCorners = valueRoundedCorners;
    settings.layout = valueLayout;
    return settings;
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.system-stat-stat-type-label")
    description: I18n.tr("panels.desktop-widgets.system-stat-stat-type-description")
    currentKey: valueStatType
    minimumWidth: 260 * Style.uiScaleRatio
    model: {
      let items = [
            {
              "key": "CPU",
              "name": I18n.tr("system-monitor.cpu-usage")
            },
            {
              "key": "Memory",
              "name": I18n.tr("common.memory")
            },
            {
              "key": "Network",
              "name": I18n.tr("bar.system-monitor.network-traffic-label")
            },
            {
              "key": "Disk",
              "name": I18n.tr("system-monitor.disk")
            }
          ];
      if (Settings.data.systemMonitor.enableDgpuMonitoring)
        items.push({
                     "key": "GPU",
                     "name": I18n.tr("panels.system-monitor.gpu-section-label")
                   });
      return items;
    }
    onSelected: key => {
                  valueStatType = key;
                  settingsChanged(saveSettings());
                }
  }

  NComboBox {
    Layout.fillWidth: true
    visible: valueStatType === "Disk"
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

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.system-stat-show-background-label")
    description: I18n.tr("panels.desktop-widgets.system-stat-show-background-description")
    checked: valueShowBackground
    onToggled: checked => {
                 valueShowBackground = checked;
                 settingsChanged(saveSettings());
               }
  }

  NToggle {
    Layout.fillWidth: true
    visible: valueShowBackground
    label: I18n.tr("panels.desktop-widgets.system-stat-rounded-corners-label")
    description: I18n.tr("panels.desktop-widgets.system-stat-rounded-corners-description")
    checked: valueRoundedCorners
    onToggled: checked => {
                 valueRoundedCorners = checked;
                 settingsChanged(saveSettings());
               }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.system-stat-layout-label")
    description: I18n.tr("panels.desktop-widgets.system-stat-layout-description")
    currentKey: valueLayout
    minimumWidth: 260 * Style.uiScaleRatio
    model: [
      {
        "key": "side",
        "name": I18n.tr("panels.desktop-widgets.system-stat-layout-side")
      },
      {
        "key": "bottom",
        "name": I18n.tr("panels.desktop-widgets.system-stat-layout-bottom")
      }
    ]
    onSelected: key => {
                  valueLayout = key;
                  settingsChanged(saveSettings());
                }
  }
}
