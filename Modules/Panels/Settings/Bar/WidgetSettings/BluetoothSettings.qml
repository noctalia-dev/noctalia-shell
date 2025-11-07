import QtQuick
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

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.displayMode = valueDisplayMode
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
}
