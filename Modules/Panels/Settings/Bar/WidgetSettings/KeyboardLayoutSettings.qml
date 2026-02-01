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

  signal settingsChanged(var settings)

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
    label: I18n.tr("bar.volume.display-mode-label")
    description: I18n.tr("bar.volume.display-mode-description")
    minimumWidth: 200
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("display-modes.on-hover")
      },
      {
        "key": "forceOpen",
        "name": I18n.tr("display-modes.force-open")
      },
      {
        "key": "alwaysHide",
        "name": I18n.tr("display-modes.always-hide")
      }
    ]
    currentKey: valueDisplayMode
    onSelected: key => {
                  valueDisplayMode = key;
                  settingsChanged(saveSettings());
                }
  }

  NToggle {
    label: I18n.tr("bar.custom-button.show-icon-label")
    description: I18n.tr("bar.keyboard-layout.show-icon-description")
    checked: valueShowIcon
    onToggled: checked => {
                 valueShowIcon = checked;
                 settingsChanged(saveSettings());
               }
  }
}
