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

  property bool valueShowIcon: widgetData.showIcon !== undefined ? widgetData.showIcon : widgetMetadata.showIcon
  property string valueHideMode: "hidden" // Default to 'Hide When Empty'
  property string valueScrollingMode: widgetData.scrollingMode || widgetMetadata.scrollingMode
  property int valueWidth: widgetData.width !== undefined ? widgetData.width : widgetMetadata.width
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons
  property bool valueAutoWidthEnabled: (widgetData.autoWidthEnabled !== undefined) ? widgetData.autoWidthEnabled : (widgetMetadata.autoWidthEnabled !== undefined ? widgetMetadata.autoWidthEnabled : false)
  property int valueAutoWidthMax: (widgetData.autoWidthMax !== undefined) ? widgetData.autoWidthMax : (widgetMetadata.autoWidthMax !== undefined ? widgetMetadata.autoWidthMax : (widgetMetadata !== undefined ? widgetMetadata.width * 2 : 0))
  property bool valueAutoWidthMinByContent: (widgetData.autoWidthMinByContent !== undefined) ? widgetData.autoWidthMinByContent : (widgetMetadata.autoWidthMinByContent !== undefined ? widgetMetadata.autoWidthMinByContent : false)
  property bool valueScrollEvenIfFits: (widgetData.scrollEvenIfFits !== undefined) ? widgetData.scrollEvenIfFits : (widgetMetadata.scrollEvenIfFits !== undefined ? widgetMetadata.scrollEvenIfFits : false)

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
    settings.colorizeIcons = valueColorizeIcons

    settings.autoWidthEnabled = valueAutoWidthEnabled
    settings.autoWidthMax = parseInt(maxWidthInput.text) || valueAutoWidthMax || widgetMetadata.maxAdaptiveWidth
    settings.autoWidthMinByContent = valueAutoWidthMinByContent
  settings.scrollEvenIfFits = valueScrollEvenIfFits

    if (valueAutoWidthEnabled) {
      delete settings.width
    } else {
      settings.width = parseInt(widthInput.text) || widgetMetadata.width
    }

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

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.adaptive-width.label")
    description: I18n.tr("bar.widget-settings.active-window.adaptive-width.description")
    checked: root.valueAutoWidthEnabled
    onToggled: function(checked) { root.valueAutoWidthEnabled = checked }
  }

  NToggle {
    Layout.fillWidth: true
    visible: root.valueAutoWidthEnabled
    label: I18n.tr("bar.widget-settings.active-window.content-as-min-width.label")
    description: I18n.tr("bar.widget-settings.active-window.content-as-min-width.description")
    checked: root.valueAutoWidthMinByContent
    onToggled: function(checked) { root.valueAutoWidthMinByContent = checked }
  }

  NTextInput {
    id: widthInput
    Layout.fillWidth: true
    visible: !root.valueAutoWidthMinByContent
    label: root.valueAutoWidthEnabled ? I18n.tr("bar.widget-settings.active-window.min-width.label") : I18n.tr("bar.widget-settings.active-window.width.label")
    description: root.valueAutoWidthEnabled ? I18n.tr("bar.widget-settings.active-window.min-width.description") : I18n.tr("bar.widget-settings.active-window.width.description")
    placeholderText: widgetMetadata.width
    text: valueWidth
  }

  NTextInput {
    id: maxWidthInput
    Layout.fillWidth: true
    visible: root.valueAutoWidthEnabled
    label: I18n.tr("bar.widget-settings.active-window.max-adaptive-width.label")
    description: I18n.tr("bar.widget-settings.active-window.max-adaptive-width.description")
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
    text: valueAutoWidthMax > 0 ? valueAutoWidthMax : ""
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

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.active-window.scroll-even-if-fits.label")
    description: I18n.tr("bar.widget-settings.active-window.scroll-even-if-fits.description")
    checked: root.valueScrollEvenIfFits
    onToggled: function(checked) { root.valueScrollEvenIfFits = checked }
  }
}
