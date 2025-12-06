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

  readonly property bool isVerticalBar: Settings.data.bar.position === "left" || Settings.data.bar.position === "right"

  // Local state
  property string valueHideMode: "hidden"
  property bool valueOnlyActiveWorkspaces: widgetData.onlyActiveWorkspaces !== undefined ? widgetData.onlyActiveWorkspaces : widgetMetadata.onlyActiveWorkspaces
  property bool valueOnlySameOutput: widgetData.onlySameOutput !== undefined ? widgetData.onlySameOutput : widgetMetadata.onlySameOutput
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons
  property bool valueShowTitle: isVerticalBar ? false : widgetData.showTitle !== undefined ? widgetData.showTitle : widgetMetadata.showTitle
  property int valueTitleWidth: widgetData.titleWidth !== undefined ? widgetData.titleWidth : widgetMetadata.titleWidth

  Component.onCompleted: {
    if (widgetData && widgetData.hideMode !== undefined) {
      valueHideMode = widgetData.hideMode;
    } else if (widgetMetadata && widgetMetadata.hideMode !== undefined) {
      valueHideMode = widgetMetadata.hideMode;
    }
  }

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.hideMode = valueHideMode;
    settings.onlySameOutput = valueOnlySameOutput;
    settings.onlyActiveWorkspaces = valueOnlyActiveWorkspaces;
    settings.colorizeIcons = valueColorizeIcons;
    settings.showTitle = valueShowTitle;
    settings.titleWidth = parseInt(titleWidthInput.text) || widgetMetadata.titleWidth;
    return settings;
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.hide-mode.label")
    description: I18n.tr("bar.widget-settings.taskbar.hide-mode.description")
    model: [
      {
        "key": "visible",
        "name": I18n.tr("options.hide-modes.visible")
      },
      {
        "key": "hidden",
        "name": I18n.tr("options.hide-modes.hidden")
      },
      {
        "key": "transparent",
        "name": I18n.tr("options.hide-modes.transparent")
      }
    ]
    currentKey: root.valueHideMode
    onSelected: key => root.valueHideMode = key
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.only-same-output.label")
    description: I18n.tr("bar.widget-settings.taskbar.only-same-output.description")
    checked: root.valueOnlySameOutput
    onToggled: checked => root.valueOnlySameOutput = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.only-active-workspaces.label")
    description: I18n.tr("bar.widget-settings.taskbar.only-active-workspaces.description")
    checked: root.valueOnlyActiveWorkspaces
    onToggled: checked => root.valueOnlyActiveWorkspaces = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.colorize-icons.label")
    description: I18n.tr("bar.widget-settings.taskbar.colorize-icons.description")
    checked: root.valueColorizeIcons
    onToggled: checked => root.valueColorizeIcons = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.show-title.label")
    description: isVerticalBar ? I18n.tr("bar.widget-settings.taskbar.show-title.description-disabled") : I18n.tr("bar.widget-settings.taskbar.show-title.description")
    checked: root.valueShowTitle
    onToggled: checked => root.valueShowTitle = checked
    enabled: !isVerticalBar
  }

  NTextInput {
    id: titleWidthInput
    visible: root.valueShowTitle && !isVerticalBar
    Layout.fillWidth: true
    label: I18n.tr("bar.widget-settings.taskbar.title-width.label")
    description: I18n.tr("bar.widget-settings.taskbar.title-width.description")
    text: widgetData.titleWidth || widgetMetadata.titleWidth
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
  }
}
