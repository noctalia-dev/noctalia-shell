import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
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

  NComboBox {
    label: I18n.tr("common.select-icon-color")
    description: I18n.tr("common.select-color-description")
    model: Color.colorKeyModel
    currentKey: valueIconColor
    onSelected: key => {
                  valueIconColor = key;
                  saveSettings();
                }
    minimumWidth: 200
  }
}
