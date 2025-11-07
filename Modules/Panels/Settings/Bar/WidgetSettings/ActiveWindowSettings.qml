import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import qs.Services

ColumnLayout {
  id: root
  spacing: Style.marginM

  // Properties to receive data from parent
  property var widgetData: null
  property var widgetMetadata: null

  // Local state
  property bool valueShowIcon: widgetData.showIcon !== undefined ? widgetData.showIcon : widgetMetadata.showIcon
  property string valueHideMode: "hidden" // Default to 'Hide When Empty'
  property string valueScrollingMode: widgetData.scrollingMode || widgetMetadata.scrollingMode
  property int valueMaxWidth: widgetData.maxWidth !== undefined ? widgetData.maxWidth : widgetMetadata.maxWidth
  property bool valueUseFixedWidth: widgetData.useFixedWidth !== undefined ? widgetData.useFixedWidth : widgetMetadata.useFixedWidth
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons

  Component.onCompleted: {
    if (widgetData && widgetData.hideMode !== undefined) {
      valueHideMode = widgetData.hideMode
    }
  }

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {})
    settings.hideMode = valueHideMode
    settings.showIcon = valueShowIcon
    settings.scrollingMode = valueScrollingMode
    settings.maxWidth = parseInt(widthInput.text) || widgetMetadata.maxWidth
    settings.useFixedWidth = valueUseFixedWidth
    settings.colorizeIcons = valueColorizeIcons
    return settings
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.hide-mode.label")
    description: I18n.tr("bar.widget-settings.active-window.hide-mode.description")
    model: [{
        "key": "visible",
        "name": I18n.tr("options.hide-modes.visible")
      }, {
        "key": "hidden",
        "name": I18n.tr("options.hide-modes.hidden")
      }, {
        "key": "transparent",
        "name": I18n.tr("options.hide-modes.transparent")
      }]
    currentKey: root.valueHideMode
    onSelected: key => root.valueHideMode = key
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.show-app-icon.label")
    description: I18n.tr("bar.widget-settings.active-window.show-app-icon.description")
    checked: root.valueShowIcon
    onToggled: checked => root.valueShowIcon = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.colorize-icons.label")
    description: I18n.tr("bar.widget-settings.active-window.colorize-icons.description")
    checked: root.valueColorizeIcons
    onToggled: checked => root.valueColorizeIcons = checked
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.max-width.label")
    description: I18n.tr("bar.widget-settings.active-window.max-width.description")
    placeholderText: widgetMetadata.maxWidth
    text: valueMaxWidth
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.use-fixed-width.label")
    description: I18n.tr("bar.widget-settings.active-window.use-fixed-width.description")
    checked: valueUseFixedWidth
    onToggled: checked => valueUseFixedWidth = checked
  }

  NComboBox {
    label: I18n.tr("bar.widget-settings.active-window.scrolling-mode.label")
    description: I18n.tr("bar.widget-settings.active-window.scrolling-mode.description")
    model: [{
        "key": "always",
        "name": I18n.tr("options.scrolling-modes.always")
      }, {
        "key": "hover",
        "name": I18n.tr("options.scrolling-modes.hover")
      }, {
        "key": "never",
        "name": I18n.tr("options.scrolling-modes.never")
      }]
    currentKey: valueScrollingMode
    onSelected: key => valueScrollingMode = key
    minimumWidth: 200
  }
}
