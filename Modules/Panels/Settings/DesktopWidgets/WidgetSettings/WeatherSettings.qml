import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  property bool valueShowBackground: widgetData.showBackground !== undefined ? widgetData.showBackground : widgetMetadata.showBackground
  property bool valueRoundedCorners: widgetData.roundedCorners !== undefined ? widgetData.roundedCorners : widgetMetadata.roundedCorners

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
    settings.roundedCorners = valueRoundedCorners;
    settingsChanged(settings);
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.desktop-widgets.clock-show-background-label")
    description: I18n.tr("panels.desktop-widgets.weather-show-background-description")
    checked: valueShowBackground
    onToggled: checked => {
                 valueShowBackground = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showBackground
  }

  NToggle {
    Layout.fillWidth: true
    visible: valueShowBackground
    label: I18n.tr("panels.desktop-widgets.clock-rounded-corners-label")
    description: I18n.tr("panels.desktop-widgets.clock-rounded-corners-description")
    checked: valueRoundedCorners
    onToggled: checked => {
                 valueRoundedCorners = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.roundedCorners
  }
}
