import QtQuick
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
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.iconColor = valueIconColor;
    settingsChanged(settings);
  }

  NColorChoice {
    label: I18n.tr("common.select-icon-color")
    currentKey: valueIconColor
    onSelected: key => {
                  valueIconColor = key;
                  saveSettings();
                }
    valueDefault: widgetMetadata.iconColor
  }
}
