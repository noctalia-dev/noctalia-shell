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

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property int valueWarningThreshold: widgetData.warningThreshold !== undefined ? widgetData.warningThreshold : widgetMetadata.warningThreshold
  property bool valueShowPowerProfiles: widgetData.showPowerProfiles !== undefined ? widgetData.showPowerProfiles : widgetMetadata.showPowerProfiles
  property bool valueShowKeepAwake: widgetData.showKeepAwake !== undefined ? widgetData.showKeepAwake : widgetMetadata.showKeepAwake
  property bool valueShowNoctaliaPerformance: widgetData.showNoctaliaPerformance !== undefined ? widgetData.showNoctaliaPerformance : widgetMetadata.showNoctaliaPerformance
  property bool valueShowBrightnessControls: widgetData.showBrightnessControls !== undefined ? widgetData.showBrightnessControls : widgetMetadata.showBrightnessControls

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.displayMode = valueDisplayMode;
    settings.warningThreshold = valueWarningThreshold;
    settings.showPowerProfiles = valueShowPowerProfiles;
    settings.showKeepAwake = valueShowKeepAwake;
    settings.showNoctaliaPerformance = valueShowNoctaliaPerformance;
    settings.showBrightnessControls = valueShowBrightnessControls;
    return settings;
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.battery.display-mode.label")
    description: I18n.tr("bar.widget-settings.battery.display-mode.description")
    minimumWidth: 134
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("options.display-mode.on-hover")
      },
      {
        "key": "alwaysShow",
        "name": I18n.tr("options.display-mode.always-show")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("options.display-mode.always-hide")
      }
    ]
    currentKey: root.valueDisplayMode
    onSelected: key => root.valueDisplayMode = key
  }

  NSpinBox {
    label: I18n.tr("bar.widget-settings.battery.low-battery-threshold.label")
    description: I18n.tr("bar.widget-settings.battery.low-battery-threshold.description")
    value: valueWarningThreshold
    suffix: "%"
    minimum: 5
    maximum: 50
    onValueChanged: valueWarningThreshold = value
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.battery.show-power-profile.label")
    description: I18n.tr("bar.widget-settings.battery.show-power-profile.description")
    checked: valueShowPowerProfiles
    onToggled: valueShowPowerProfiles = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.battery.show-keep-awake.label")
    description: I18n.tr("bar.widget-settings.battery.show-keep-awake.description")
    checked: valueShowKeepAwake
    onToggled: valueShowKeepAwake = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.battery.show-noctalia-performance.label")
    description: I18n.tr("bar.widget-settings.battery.show-noctalia-performance.description")
    checked: valueShowNoctaliaPerformance
    onToggled: valueShowNoctaliaPerformance = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.battery.show-brightness-controls.label")
    description: I18n.tr("bar.widget-settings.battery.show-brightness-controls.description")
    checked: valueShowBrightnessControls
    onToggled: valueShowBrightnessControls = checked
  }
}
