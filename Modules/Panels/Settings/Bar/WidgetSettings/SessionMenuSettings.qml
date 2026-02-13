import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.System
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM
  width: 700

  // Properties to receive data from parent
  property var screen: null
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : (widgetData.colorName !== undefined ? widgetData.colorName : widgetMetadata.iconColor)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.iconColor = valueIconColor;
    settingsChanged(settings);
  }

  NComboBox {
    label: I18n.tr("common.select-icon-color")
    description: I18n.tr("common.select-color-description")
    model: Color.colorKeyModel
    currentKey: root.valueIconColor
    onSelected: key => {
                  root.valueIconColor = key;
                  saveSettings();
                }
    minimumWidth: 200
  }
}
