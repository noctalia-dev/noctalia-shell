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

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.showBackground = valueShowBackground;
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
  }
}
