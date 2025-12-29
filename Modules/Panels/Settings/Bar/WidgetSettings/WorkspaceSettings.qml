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

  property string valueLabelMode: widgetData.labelMode !== undefined ? widgetData.labelMode : widgetMetadata.labelMode
  property bool valueHideUnoccupied: widgetData.hideUnoccupied !== undefined ? widgetData.hideUnoccupied : widgetMetadata.hideUnoccupied
  property bool valueFollowFocusedScreen: widgetData.followFocusedScreen !== undefined ? widgetData.followFocusedScreen : widgetMetadata.followFocusedScreen
  property int valueCharacterCount: widgetData.characterCount !== undefined ? widgetData.characterCount : widgetMetadata.characterCount

  // Grouped mode settings
  property bool valueShowApplications: widgetData.showApplications !== undefined ? widgetData.showApplications : widgetMetadata.showApplications
  property bool valueShowLabelsOnlyWhenOccupied: widgetData.showLabelsOnlyWhenOccupied !== undefined ? widgetData.showLabelsOnlyWhenOccupied : widgetMetadata.showLabelsOnlyWhenOccupied
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons
  property real valueUnfocusedIconsOpacity: widgetData.unfocusedIconsOpacity !== undefined ? widgetData.unfocusedIconsOpacity : widgetMetadata.unfocusedIconsOpacity
  property real valueGroupedBorderOpacity: widgetData.groupedBorderOpacity !== undefined ? widgetData.groupedBorderOpacity : widgetMetadata.groupedBorderOpacity
  property bool valueEnableScrollWheel: widgetData.enableScrollWheel !== undefined ? widgetData.enableScrollWheel : widgetMetadata.enableScrollWheel

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.labelMode = valueLabelMode;
    settings.hideUnoccupied = valueHideUnoccupied;
    settings.characterCount = valueCharacterCount;
    settings.followFocusedScreen = valueFollowFocusedScreen;
    settings.showApplications = valueShowApplications;
    settings.showLabelsOnlyWhenOccupied = valueShowLabelsOnlyWhenOccupied;
    settings.colorizeIcons = valueColorizeIcons;
    settings.unfocusedIconsOpacity = valueUnfocusedIconsOpacity;
    settings.groupedBorderOpacity = valueGroupedBorderOpacity;
    settings.enableScrollWheel = valueEnableScrollWheel;
    return settings;
  }

  NComboBox {
    id: labelModeCombo
    label: I18n.tr("bar.widget-settings.workspace.label-mode.label")
    description: I18n.tr("bar.widget-settings.workspace.label-mode.description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("options.workspace-labels.none")
      },
      {
        "key": "index",
        "name": I18n.tr("options.workspace-labels.index")
      },
      {
        "key": "name",
        "name": I18n.tr("options.workspace-labels.name")
      },
      {
        "key": "index+name",
        "name": I18n.tr("options.workspace-labels.index+name")
      }
    ]
    currentKey: widgetData.labelMode || widgetMetadata.labelMode
    onSelected: key => valueLabelMode = key
    minimumWidth: 200
  }

  NSpinBox {
    label: I18n.tr("bar.widget-settings.workspace.character-count.label")
    description: I18n.tr("bar.widget-settings.workspace.character-count.description")
    from: 1
    to: 10
    value: valueCharacterCount
    onValueChanged: valueCharacterCount = value
    visible: valueLabelMode === "name"
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.workspace.hide-unoccupied.label")
    description: I18n.tr("bar.widget-settings.workspace.hide-unoccupied.description")
    checked: valueHideUnoccupied
    onToggled: checked => valueHideUnoccupied = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.workspace.show-labels-only-when-occupied.label")
    description: I18n.tr("bar.widget-settings.workspace.show-labels-only-when-occupied.description")
    checked: valueShowLabelsOnlyWhenOccupied
    onToggled: checked => valueShowLabelsOnlyWhenOccupied = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.workspace.follow-focused-screen.label")
    description: I18n.tr("bar.widget-settings.workspace.follow-focused-screen.description")
    checked: valueFollowFocusedScreen
    onToggled: checked => valueFollowFocusedScreen = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.workspace.enable-scrollwheel.label")
    description: I18n.tr("bar.widget-settings.workspace.enable-scrollwheel.description")
    checked: valueEnableScrollWheel
    onToggled: checked => valueEnableScrollWheel = checked
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.workspace.show-applications.label")
    description: I18n.tr("bar.widget-settings.workspace.show-applications.description")
    checked: valueShowApplications
    onToggled: checked => valueShowApplications = checked
  }

  NToggle {
    label: I18n.tr("bar.widget-settings.active-window.colorize-icons.label")
    description: I18n.tr("bar.widget-settings.active-window.colorize-icons.description")
    checked: valueColorizeIcons
    onToggled: checked => valueColorizeIcons = checked
    visible: valueShowApplications
  }

  NValueSlider {
    label: I18n.tr("bar.widget-settings.workspace.unfocused-icons-opacity.label")
    description: I18n.tr("bar.widget-settings.workspace.unfocused-icons-opacity.description")
    from: 0
    to: 1
    stepSize: 0.01
    value: valueUnfocusedIconsOpacity
    onMoved: value => valueUnfocusedIconsOpacity = value
    text: Math.floor(valueUnfocusedIconsOpacity * 100) + "%"
    visible: valueShowApplications
  }

  NValueSlider {
    label: I18n.tr("bar.widget-settings.workspace.grouped-border-opacity.label")
    description: I18n.tr("bar.widget-settings.workspace.grouped-border-opacity.description")
    from: 0
    to: 1
    stepSize: 0.01
    value: valueGroupedBorderOpacity
    onMoved: value => valueGroupedBorderOpacity = value
    text: Math.floor(valueGroupedBorderOpacity * 100) + "%"
    visible: valueShowApplications
  }
}
