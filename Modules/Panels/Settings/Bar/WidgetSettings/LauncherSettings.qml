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
  property var widgetData: null
  property var widgetMetadata: null

  signal settingsChanged(var settings)

  // Local state
  property bool valueUsePrimaryColor: widgetData.usePrimaryColor !== undefined ? widgetData.usePrimaryColor : (widgetMetadata ? widgetMetadata.usePrimaryColor : false)

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.usePrimaryColor = valueUsePrimaryColor;
    return settings;
  }

  NToggle {
    label: I18n.tr("bar.clock.use-primary-color-label")
    description: I18n.tr("bar.clock.use-primary-color-description")
    checked: valueUsePrimaryColor
    onToggled: checked => {
                 valueUsePrimaryColor = checked;
                 settingsChanged(saveSettings());
               }
  }
}
