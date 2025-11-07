import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property int valueWarningThreshold: widgetData.warningThreshold !== undefined ? widgetData.warningThreshold : widgetMetadata.warningThreshold

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.displayMode = valueDisplayMode
    settings.warningThreshold = valueWarningThreshold
    return settings
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.battery.display-mode.label")
    description: I18n.tr("bar.widget-settings.battery.display-mode.description")
    minimumWidth: 134
    model: [{
        "key": "onhover",
        "name": I18n.tr("options.display-mode.on-hover")
      }, {
        "key": "alwaysShow",
        "name": I18n.tr("options.display-mode.always-show")
      }, {
        "key": "alwaysHide",
        "name": I18n.tr("options.display-mode.always-hide")
      }]
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
}
