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
  property bool valueShowIcon: widgetData.showIcon !== undefined ? widgetData.showIcon : widgetMetadata.showIcon
  property string valueHideMode: widgetData.hideMode !== undefined ? widgetData.hideMode : widgetMetadata.hideMode
  property string valueScrollingMode: widgetData.scrollingMode || widgetMetadata.scrollingMode
  property int valueMaxWidth: widgetData.maxWidth !== undefined ? widgetData.maxWidth : widgetMetadata.maxWidth
  property bool valueUseFixedWidth: widgetData.useFixedWidth !== undefined ? widgetData.useFixedWidth : widgetMetadata.useFixedWidth
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons
  property string valueTextColor: widgetData.textColor !== undefined ? widgetData.textColor : widgetMetadata.textColor

  Component.onCompleted: {
    if (widgetData && widgetData.hideMode !== undefined) {
      valueHideMode = widgetData.hideMode;
    }
  }

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.hideMode = valueHideMode;
    settings.showIcon = valueShowIcon;
    settings.scrollingMode = valueScrollingMode;
    settings.maxWidth = parseInt(widthInput.text) || widgetMetadata.maxWidth;
    settings.useFixedWidth = valueUseFixedWidth;
    settings.colorizeIcons = valueColorizeIcons;
    settings.textColor = valueTextColor;
    settingsChanged(settings);
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.hide-mode-label")
    description: I18n.tr("bar.active-window.hide-mode-description")
    model: [
      {
        "key": "visible",
        "name": I18n.tr("hide-modes.visible")
      },
      {
        "key": "hidden",
        "name": I18n.tr("hide-modes.hidden")
      },
      {
        "key": "transparent",
        "name": I18n.tr("hide-modes.transparent")
      }
    ]
    currentKey: root.valueHideMode
    onSelected: key => {
                  root.valueHideMode = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.hideMode
  }

  NColorChoice {
    label: I18n.tr("common.select-color")
    currentKey: valueTextColor
    onSelected: key => {
                  valueTextColor = key;
                  saveSettings();
                }
    defaultValue: widgetMetadata.textColor
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.active-window.show-app-icon-label")
    description: I18n.tr("bar.active-window.show-app-icon-description")
    checked: root.valueShowIcon
    onToggled: checked => {
                 root.valueShowIcon = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.showIcon
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.tray.colorize-icons-label")
    description: I18n.tr("bar.active-window.colorize-icons-description")
    checked: root.valueColorizeIcons
    onToggled: checked => {
                 root.valueColorizeIcons = checked;
                 saveSettings();
               }
    visible: root.valueShowIcon
    defaultValue: widgetMetadata.colorizeIcons
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.max-width-label")
    description: I18n.tr("bar.media-mini.max-width-description")
    placeholderText: widgetMetadata.maxWidth
    text: valueMaxWidth
    onEditingFinished: saveSettings()
    defaultValue: String(widgetMetadata.maxWidth)
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.media-mini.use-fixed-width-label")
    description: I18n.tr("bar.media-mini.use-fixed-width-description")
    checked: valueUseFixedWidth
    onToggled: checked => {
                 valueUseFixedWidth = checked;
                 saveSettings();
               }
    defaultValue: widgetMetadata.useFixedWidth
  }

  NComboBox {
    label: I18n.tr("bar.media-mini.scrolling-mode-label")
    description: I18n.tr("bar.active-window.scrolling-mode-description")
    model: [
      {
        "key": "always",
        "name": I18n.tr("options.scrolling-modes.always")
      },
      {
        "key": "hover",
        "name": I18n.tr("options.scrolling-modes.hover")
      },
      {
        "key": "never",
        "name": I18n.tr("options.scrolling-modes.never")
      }
    ]
    currentKey: valueScrollingMode
    defaultValue: widgetMetadata.scrollingMode
    onSelected: key => {
                  valueScrollingMode = key;
                  saveSettings();
                }
    minimumWidth: 200
  }
}
