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

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.displayMode = valueDisplayMode
    return settings
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.keyboard-layout.display-mode.label")
    description: I18n.tr("bar.widget-settings.keyboard-layout.display-mode.description")
    minimumWidth: 134
    model: [{
        "key": "onhover",
        "name": I18n.tr("options.display-mode.on-hover")
      }, {
        "key": "forceOpen",
        "name": I18n.tr("options.display-mode.force-open")
      }, {
        "key": "alwaysHide",
        "name": I18n.tr("options.display-mode.always-hide")
      }]
    currentKey: valueDisplayMode
    onSelected: key => valueDisplayMode = key
  }
}
