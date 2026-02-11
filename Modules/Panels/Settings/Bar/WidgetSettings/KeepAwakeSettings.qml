import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    return settings;
  }

  NComboBox {
    label: I18n.tr("common.select-icon-color")
    description: I18n.tr("common.select-color-description")
    model: Color.colorKeyModel
    currentKey: valueIconColor
    onSelected: key => {
                  valueIconColor = key;
                  settingsChanged(saveSettings());
                }
    minimumWidth: 200
  }

  NComboBox {
    label: I18n.tr("common.select-color")
    description: I18n.tr("common.select-color-description")
    model: Color.colorKeyModel
    currentKey: valueTextColor
    onSelected: key => {
                  valueTextColor = key;
                  settingsChanged(saveSettings());
                }
    minimumWidth: 200
  }
}
