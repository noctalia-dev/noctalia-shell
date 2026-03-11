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

  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    settingsChanged(settings);
  }

  NColorChoice {
    label: I18n.tr("common.select-icon-color")
    currentKey: valueIconColor
    onSelected: key => {
                  valueIconColor = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.iconColor
  }

  NColorChoice {
    currentKey: valueTextColor
    onSelected: key => {
                  valueTextColor = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.textColor
  }
}
