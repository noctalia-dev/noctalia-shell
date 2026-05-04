import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Hardware
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property string valueDeviceNativePath: widgetData.deviceNativePath !== undefined ? widgetData.deviceNativePath : widgetMetadata.deviceNativePath
  property bool valueShowPowerProfiles: widgetData.showPowerProfiles !== undefined ? widgetData.showPowerProfiles : widgetMetadata.showPowerProfiles
  property bool valueShowNoctaliaPerformance: widgetData.showNoctaliaPerformance !== undefined ? widgetData.showNoctaliaPerformance : widgetMetadata.showNoctaliaPerformance
  property bool valueHideIfNotDetected: widgetData.hideIfNotDetected !== undefined ? widgetData.hideIfNotDetected : widgetMetadata.hideIfNotDetected
  property bool valueHideIfIdle: widgetData.hideIfIdle !== undefined ? widgetData.hideIfIdle : widgetMetadata.hideIfIdle

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    if (widgetData && widgetData.id) {
      settings.id = widgetData.id;
    }
    settings.displayMode = valueDisplayMode;
    settings.showPowerProfiles = valueShowPowerProfiles;
    settings.showNoctaliaPerformance = valueShowNoctaliaPerformance;
    settings.hideIfNotDetected = valueHideIfNotDetected;
    settings.hideIfIdle = valueHideIfIdle;
    settings.deviceNativePath = valueDeviceNativePath;
    settingsChanged(settings);
  }

  NComboBox {
    id: deviceComboBox
    Layout.fillWidth: true
    label: I18n.tr("bar.battery.device-label")
    description: I18n.tr("bar.battery.device-description")
    minimumWidth: 240
    model: BatteryService.deviceModel
    currentKey: root.valueDeviceNativePath
    onSelected: key => {
                  root.valueDeviceNativePath = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.deviceNativePath
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("common.display-mode")
    description: I18n.tr("bar.battery.display-mode-description")
    minimumWidth: 240
    model: [
      {
        "key": "graphic",
        "name": I18n.tr("bar.battery.display-mode-graphic")
      },
      {
        "key": "graphic-clean",
        "name": I18n.tr("bar.battery.display-mode-graphic-clean")
      },
      {
        "key": "icon-hover",
        "name": I18n.tr("bar.battery.display-mode-icon-hover")
      },
      {
        "key": "icon-always",
        "name": I18n.tr("bar.battery.display-mode-icon-always")
      },
      {
        "key": "icon-only",
        "name": I18n.tr("bar.battery.display-mode-icon-only")
      }
    ]
    currentKey: root.valueDisplayMode
    onSelected: key => {
                  root.valueDisplayMode = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.displayMode
  }

  NToggle {
    label: I18n.tr("bar.battery.hide-if-not-detected-label")
    description: I18n.tr("bar.battery.hide-if-not-detected-description")
    checked: valueHideIfNotDetected
    onToggled: checked => {
                 valueHideIfNotDetected = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.hideIfNotDetected
  }

  NToggle {
    label: I18n.tr("bar.battery.hide-if-idle-label")
    description: I18n.tr("bar.battery.hide-if-idle-description")
    checked: valueHideIfIdle
    onToggled: checked => {
                 valueHideIfIdle = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.hideIfIdle
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    label: I18n.tr("bar.battery.show-power-profile-label")
    description: I18n.tr("bar.battery.show-power-profile-description")
    checked: valueShowPowerProfiles
    onToggled: checked => {
                 valueShowPowerProfiles = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showPowerProfiles
  }

  NToggle {
    label: I18n.tr("bar.battery.show-noctalia-performance-label")
    description: I18n.tr("bar.battery.show-noctalia-performance-description")
    checked: valueShowNoctaliaPerformance
    onToggled: checked => {
                 valueShowNoctaliaPerformance = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showNoctaliaPerformance
  }
}
