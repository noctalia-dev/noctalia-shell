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

  // Local state
  property bool valueHideWhenIdle: widgetData.hideWhenIdle !== undefined ? widgetData.hideWhenIdle : widgetMetadata.hideWhenIdle
  property string valueColorName: widgetData.colorName !== undefined ? widgetData.colorName : widgetMetadata.colorName

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.width = parseInt(widthInput.text) || widgetMetadata.width;
    settings.hideWhenIdle = valueHideWhenIdle;
    settings.colorName = valueColorName;
    settingsChanged(settings);
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("common.width")
    description: I18n.tr("bar.audio-visualizer.width-description")
    text: widgetData.width || widgetMetadata.width
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
    onEditingFinished: saveSettings()
    defaultValue: String(widgetMetadata.width)
  }

  NColorChoice {
    Layout.fillWidth: true
    label: I18n.tr("bar.audio-visualizer.color-name-label")
    description: I18n.tr("bar.audio-visualizer.color-name-description")
    currentKey: root.valueColorName
    onSelected: key => {
                  root.valueColorName = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.colorName
  }

  NToggle {
    label: I18n.tr("bar.audio-visualizer.hide-when-idle-label")
    description: I18n.tr("bar.audio-visualizer.hide-when-idle-description")
    checked: valueHideWhenIdle
    onToggled: checked => {
                 valueHideWhenIdle = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.hideWhenIdle
  }
}
