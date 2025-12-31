import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property bool valueShowIcon: widgetData.showIcon !== undefined ? widgetData.showIcon : widgetMetadata.showIcon

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.displayMode = valueDisplayMode;
    settings.showIcon = valueShowIcon;
    return settings;
  }

  NComboBox {
    visible: valueShowIcon // Hide display mode setting when icon is disabled
    label: I18n.tr("bar.widget-settings.keyboard-layout.display-mode.label")
    description: I18n.tr("bar.widget-settings.keyboard-layout.display-mode.description")
    minimumWidth: 134
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("options.display-mode.on-hover")
      },
      {
        "key": "forceOpen",
        "name": I18n.tr("options.display-mode.force-open")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("options.display-mode.always-hide")
      }
    ]
    currentKey: valueDisplayMode
    onSelected: key => valueDisplayMode = key
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.keyboard-layout.show-icon.label")
    description: I18n.tr("bar.widget-settings.keyboard-layout.show-icon.description")
    checked: valueShowIcon
    onToggled: checked => valueShowIcon = checked
  }
}
