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

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.width = parseInt(widthInput.text) || widgetMetadata.width
    return settings
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.spacer.width.label")
    description: I18n.tr("bar.widget-settings.spacer.width.description")
    text: widgetData.width || widgetMetadata.width
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
  }
}
