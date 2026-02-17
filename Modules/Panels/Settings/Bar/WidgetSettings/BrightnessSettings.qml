import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
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
  property string valueIconColor: widgetData.iconColor !== undefined ? widgetData.iconColor : widgetMetadata.iconColor
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor
  property bool valueApplyScrollToAllMonitors: widgetData.applyScrollToAllMonitors !== undefined ? widgetData.applyScrollToAllMonitors : (Settings.data.brightness.syncAllMonitors !== undefined ? Settings.data.brightness.syncAllMonitors : widgetMetadata.applyScrollToAllMonitors)

  readonly property bool hasMultipleMonitors: (Quickshell.screens || []).length > 1

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.displayMode = valueDisplayMode;
    settings.iconColor = valueIconColor;
    settings.textColor = valueTextColor;
    settings.applyScrollToAllMonitors = valueApplyScrollToAllMonitors;
    Settings.data.brightness.syncAllMonitors = valueApplyScrollToAllMonitors;
    settingsChanged(settings);
  }

  NComboBox {
    label: I18n.tr("common.display-mode")
    description: I18n.tr("bar.volume.display-mode-description")
    minimumWidth: 200
    model: [
      {
        "key": "onhover",
        "name": I18n.tr("display-modes.on-hover")
      },
      {
        "key": "alwaysShow",
        "name": I18n.tr("display-modes.always-show")
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

  NColorChoice {
    label: I18n.tr("common.select-icon-color")
    currentKey: valueIconColor
    onSelected: key => {
                  valueIconColor = key;
                  saveSettings();
                }
  }

  NColorChoice {
    currentKey: valueTextColor
    onSelected: key => {
                  valueTextColor = key;
                  saveSettings();
                }
  }

  NToggle {
    visible: hasMultipleMonitors
    Layout.fillWidth: true
    label: I18n.tr("bar.brightness.apply-scroll-all-label")
    description: I18n.tr("bar.brightness.apply-scroll-all-description")
    checked: valueApplyScrollToAllMonitors
    onToggled: checked => {
                 valueApplyScrollToAllMonitors = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.applyScrollToAllMonitors
  }
}
