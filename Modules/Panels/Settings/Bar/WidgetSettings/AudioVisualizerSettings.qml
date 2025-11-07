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
  property bool valueHideWhenIdle: widgetData.hideWhenIdle !== undefined ? widgetData.hideWhenIdle : widgetMetadata.hideWhenIdle
  property string valueColorName: widgetData.colorName !== undefined ? widgetData.colorName : widgetMetadata.colorName

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.width = parseInt(widthInput.text) || widgetMetadata.width
    settings.hideWhenIdle = valueHideWhenIdle
    settings.colorName = valueColorName
    return settings
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.audio-visualizer.width.label")
    description: I18n.tr("bar.widget-settings.audio-visualizer.width.description")
    text: widgetData.width || widgetMetadata.width
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.audio-visualizer.color-name.label")
    description: I18n.tr("bar.widget-settings.audio-visualizer.color-name.description")
    model: [{
        "key": "primary",
        "name": I18n.tr("options.colors.primary")
      }, {
        "key": "secondary",
        "name": I18n.tr("options.colors.secondary")
      }, {
        "key": "tertiary",
        "name": I18n.tr("options.colors.tertiary")
      }, {
        "key": "onSurface",
        "name": I18n.tr("options.colors.onSurface")
      }, {
        "key": "error",
        "name": I18n.tr("options.colors.error")
      }]
    currentKey: root.valueColorName
    onSelected: key => root.valueColorName = key
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.audio-visualizer.hide-when-idle.label")
    description: I18n.tr("bar.widget-settings.audio-visualizer.hide-when-idle.description")
    checked: valueHideWhenIdle
    onToggled: checked => valueHideWhenIdle = checked
  }
}
