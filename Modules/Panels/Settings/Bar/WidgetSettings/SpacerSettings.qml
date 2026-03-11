import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.width = parseInt(widthInput.text) || widgetMetadata.width;
    settingsChanged(settings);
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("common.width")
    description: I18n.tr("bar.spacer.width-description")
    text: widgetData.width || widgetMetadata.width
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
    onEditingFinished: saveSettings()
    defaultValue: String(widgetMetadata.width)
  }
}
