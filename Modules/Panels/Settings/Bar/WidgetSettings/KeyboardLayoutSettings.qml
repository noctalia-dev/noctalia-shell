import QtQuick
import QtQuick.Controls
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
  property string valueDisplayMode: widgetData.displayMode !== undefined ? widgetData.displayMode : widgetMetadata.displayMode
  property bool valueShowIcon: widgetData.showIcon !== undefined ? widgetData.showIcon : widgetMetadata.showIcon
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.displayMode = valueDisplayMode;
    settings.showIcon = valueShowIcon;
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    settingsChanged(settings);
  }

  NComboBox {
    visible: valueShowIcon // Hide display mode setting when icon is disabled
    label: I18n.tr("common.display-mode")
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
                  saveSettings();
                }
  }

  NToggle {
    label: I18n.tr("bar.custom-button.show-icon-label")
    description: I18n.tr("bar.keyboard-layout.show-icon-description")
    checked: valueShowIcon
    onToggled: checked => {
                 valueShowIcon = checked;
                 saveSettings();
               }
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

  NComboBox {
    label: I18n.tr("common.select-color")
    description: I18n.tr("common.select-color-description")
    model: Color.colorKeyModel
    currentKey: valueTextColor
    onSelected: key => {
                  valueTextColor = key;
                  saveSettings();
                }
    minimumWidth: 200
  }
}
