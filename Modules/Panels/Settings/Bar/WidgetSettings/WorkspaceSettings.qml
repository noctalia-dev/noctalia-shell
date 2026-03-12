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

  property string valueLabelMode: widgetData.labelMode !== undefined ? widgetData.labelMode : widgetMetadata.labelMode
  property bool valueHideUnoccupied: widgetData.hideUnoccupied !== undefined ? widgetData.hideUnoccupied : widgetMetadata.hideUnoccupied
  property bool valueFollowFocusedScreen: widgetData.followFocusedScreen !== undefined ? widgetData.followFocusedScreen : widgetMetadata.followFocusedScreen
  property int valueCharacterCount: widgetData.characterCount !== undefined ? widgetData.characterCount : widgetMetadata.characterCount

  // Grouped mode settings
  property bool valueShowApplications: widgetData.showApplications !== undefined ? widgetData.showApplications : widgetMetadata.showApplications
  property bool valueShowApplicationsHover: widgetData.showApplicationsHover !== undefined ? widgetData.showApplicationsHover : widgetMetadata.showApplicationsHover
  property bool valueShowLabelsOnlyWhenOccupied: widgetData.showLabelsOnlyWhenOccupied !== undefined ? widgetData.showLabelsOnlyWhenOccupied : widgetMetadata.showLabelsOnlyWhenOccupied
  property bool valueColorizeIcons: widgetData.colorizeIcons !== undefined ? widgetData.colorizeIcons : widgetMetadata.colorizeIcons
  property real valueUnfocusedIconsOpacity: widgetData.unfocusedIconsOpacity !== undefined ? widgetData.unfocusedIconsOpacity : widgetMetadata.unfocusedIconsOpacity
  property real valueGroupedBorderOpacity: widgetData.groupedBorderOpacity !== undefined ? widgetData.groupedBorderOpacity : widgetMetadata.groupedBorderOpacity
  property bool valueEnableScrollWheel: widgetData.enableScrollWheel !== undefined ? widgetData.enableScrollWheel : widgetMetadata.enableScrollWheel
  property real valueIconScale: widgetData.iconScale !== undefined ? widgetData.iconScale : widgetMetadata.iconScale
  property string valueFocusedColor: widgetData.focusedColor !== undefined ? widgetData.focusedColor : widgetMetadata.focusedColor
  property string valueOccupiedColor: widgetData.occupiedColor !== undefined ? widgetData.occupiedColor : widgetMetadata.occupiedColor
  property string valueEmptyColor: widgetData.emptyColor !== undefined ? widgetData.emptyColor : widgetMetadata.emptyColor
  property bool valueShowBadge: widgetData.showBadge !== undefined ? widgetData.showBadge : widgetMetadata.showBadge
  property real valuePillSize: widgetData.pillSize !== undefined ? widgetData.pillSize : widgetMetadata.pillSize
  property string valueFontWeight: widgetData.fontWeight !== undefined ? widgetData.fontWeight : widgetMetadata.fontWeight

  function saveSettings() {
    var settings = Object.assign({}, widgetData || {});
    settings.labelMode = valueLabelMode;
    settings.hideUnoccupied = valueHideUnoccupied;
    settings.characterCount = valueCharacterCount;
    settings.followFocusedScreen = valueFollowFocusedScreen;
    settings.showApplications = valueShowApplications;
    settings.showApplicationsHover = valueShowApplicationsHover;
    settings.showLabelsOnlyWhenOccupied = valueShowLabelsOnlyWhenOccupied;
    settings.colorizeIcons = valueColorizeIcons;
    settings.unfocusedIconsOpacity = valueUnfocusedIconsOpacity;
    settings.groupedBorderOpacity = valueGroupedBorderOpacity;
    settings.enableScrollWheel = valueEnableScrollWheel;
    settings.iconScale = valueIconScale;
    settings.focusedColor = valueFocusedColor;
    settings.occupiedColor = valueOccupiedColor;
    settings.emptyColor = valueEmptyColor;
    settings.showBadge = valueShowBadge;
    settings.pillSize = valuePillSize;
    settings.fontWeight = valueFontWeight;
    settingsChanged(settings);
  }

  NComboBox {
    id: labelModeCombo
    label: I18n.tr("bar.workspace.label-mode-label")
    description: I18n.tr("bar.workspace.label-mode-description")
    model: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
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
        "name": I18n.tr("options.workspace-labels.index-and-name")
      }
    ]
    currentKey: widgetData.labelMode || widgetMetadata.labelMode
    onSelected: key => {
                  valueLabelMode = key;
                  saveSettings();
                }
    minimumWidth: 200
  }

  NSpinBox {
    label: I18n.tr("bar.workspace.character-count-label")
    description: I18n.tr("bar.workspace.character-count-description")
    from: 1
    to: 10
    value: valueCharacterCount
    onValueChanged: {
      valueCharacterCount = value;
      saveSettings();
    }
    visible: valueLabelMode === "name"
  }

  NValueSlider {
    label: I18n.tr("bar.workspace.pill-size-label")
    description: I18n.tr("bar.workspace.pill-size-description")
    from: 0.4
    to: 1.0
    stepSize: 0.01
    value: valuePillSize
    defaultValue: widgetMetadata.pillSize
    showReset: true
    onMoved: value => {
               valuePillSize = value;
               saveSettings();
             }
    text: Math.round(valuePillSize * 100) + "%"
    visible: !valueShowApplications
  }

  NComboBox {
    id: fontWeightCombo
    label: I18n.tr("bar.workspace.font-weight-label")
    description: I18n.tr("bar.workspace.font-weight-description")
    model: [
      {
        "key": "regular",
        "name": I18n.tr("common.font-weight-regular")
      },
      {
        "key": "medium",
        "name": I18n.tr("common.font-weight-medium")
      },
      {
        "key": "semibold",
        "name": I18n.tr("common.font-weight-semibold")
      },
      {
        "key": "bold",
        "name": I18n.tr("common.font-weight-bold")
      },
    ]
    currentKey: widgetData.fontWeight || widgetMetadata.fontWeight
    onSelected: key => {
                  valueFontWeight = key;
                  saveSettings();
                }
    minimumWidth: 200
  }

  NToggle {
    label: I18n.tr("bar.workspace.hide-unoccupied-label")
    description: I18n.tr("bar.workspace.hide-unoccupied-description")
    checked: valueHideUnoccupied
    onToggled: checked => {
                 valueHideUnoccupied = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.workspace.show-labels-only-when-occupied-label")
    description: I18n.tr("bar.workspace.show-labels-only-when-occupied-description")
    checked: valueShowLabelsOnlyWhenOccupied
    onToggled: checked => {
                 valueShowLabelsOnlyWhenOccupied = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.workspace.follow-focused-screen-label")
    description: I18n.tr("bar.workspace.follow-focused-screen-description")
    checked: valueFollowFocusedScreen
    onToggled: checked => {
                 valueFollowFocusedScreen = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.workspace.enable-scrollwheel-label")
    description: I18n.tr("bar.workspace.enable-scrollwheel-description")
    checked: valueEnableScrollWheel
    onToggled: checked => {
                 valueEnableScrollWheel = checked;
                 saveSettings();
               }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NToggle {
    label: I18n.tr("bar.workspace.show-applications-label")
    description: I18n.tr("bar.workspace.show-applications-description")
    checked: valueShowApplications
    onToggled: checked => {
                 valueShowApplications = checked;
                 saveSettings();
               }
  }

  NToggle {
    label: I18n.tr("bar.workspace.show-applications-hover-label")
    description: I18n.tr("bar.workspace.show-applications-hover-description")
    checked: valueShowApplicationsHover
    onToggled: checked => {
                 valueShowApplicationsHover = checked;
                 saveSettings();
               }
    visible: valueShowApplications
  }

  NToggle {
    label: I18n.tr("bar.workspace.show-badge-label")
    description: I18n.tr("bar.workspace.show-badge-description")
    checked: valueShowBadge
    onToggled: checked => {
                 valueShowBadge = checked;
                 saveSettings();
               }
    visible: valueShowApplications
  }

  NToggle {
    label: I18n.tr("bar.tray.colorize-icons-label")
    description: I18n.tr("bar.active-window.colorize-icons-description")
    checked: valueColorizeIcons
    onToggled: checked => {
                 valueColorizeIcons = checked;
                 saveSettings();
               }
    visible: valueShowApplications
  }

  NValueSlider {
    label: I18n.tr("bar.workspace.unfocused-icons-opacity-label")
    description: I18n.tr("bar.workspace.unfocused-icons-opacity-description")
    from: 0
    to: 1
    stepSize: 0.01
    showReset: true
    value: valueUnfocusedIconsOpacity
    defaultValue: widgetMetadata.unfocusedIconsOpacity
    onMoved: value => {
               valueUnfocusedIconsOpacity = value;
               saveSettings();
             }
    text: Math.floor(valueUnfocusedIconsOpacity * 100) + "%"
    visible: valueShowApplications
  }

  NValueSlider {
    label: I18n.tr("bar.workspace.grouped-border-opacity-label")
    description: I18n.tr("bar.workspace.grouped-border-opacity-description")
    from: 0
    to: 1
    stepSize: 0.01
    showReset: true
    value: valueGroupedBorderOpacity
    defaultValue: widgetMetadata.groupedBorderOpacity
    onMoved: value => {
               valueGroupedBorderOpacity = value;
               saveSettings();
             }
    text: Math.floor(valueGroupedBorderOpacity * 100) + "%"
    visible: valueShowApplications
  }

  NValueSlider {
    label: I18n.tr("bar.taskbar.icon-scale-label")
    description: I18n.tr("bar.taskbar.icon-scale-description")
    from: 0.5
    to: 1
    stepSize: 0.01
    showReset: true
    value: valueIconScale
    defaultValue: widgetMetadata.iconScale
    onMoved: value => {
               valueIconScale = value;
               saveSettings();
             }
    text: Math.round(valueIconScale * 100) + "%"
    visible: valueShowApplications
  }

  NDivider {
    Layout.fillWidth: true
  }

  NColorChoice {
    label: I18n.tr("bar.workspace.focused-color-label")
    description: I18n.tr("bar.workspace.focused-color-description")
    currentKey: valueFocusedColor
    onSelected: key => {
                  valueFocusedColor = key;
                  saveSettings();
                }
  }

  NColorChoice {
    label: I18n.tr("bar.workspace.occupied-color-label")
    description: I18n.tr("bar.workspace.occupied-color-description")
    currentKey: valueOccupiedColor
    onSelected: key => {
                  valueOccupiedColor = key;
                  saveSettings();
                }
  }

  NColorChoice {
    label: I18n.tr("bar.workspace.empty-color-label")
    description: I18n.tr("bar.workspace.empty-color-description")
    currentKey: valueEmptyColor
    onSelected: key => {
                  valueEmptyColor = key;
                  saveSettings();
                }
  }
}
