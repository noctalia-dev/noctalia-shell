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
  property bool valueSmartWidth: widgetData.smartWidth !== undefined ? widgetData.smartWidth : widgetMetadata.smartWidth
  property int valueMaxTaskbarWidth: widgetData.maxTaskbarWidth !== undefined ? widgetData.maxTaskbarWidth : widgetMetadata.maxTaskbarWidth
  property int valueTitleWidth: widgetData.titleWidth !== undefined ? widgetData.titleWidth : widgetMetadata.titleWidth
  property bool valueShowPinnedApps: widgetData.showPinnedApps !== undefined ? widgetData.showPinnedApps : widgetMetadata.showPinnedApps
  property real valueIconScale: widgetData.iconScale !== undefined ? widgetData.iconScale : widgetMetadata.iconScale
  property string valueLeftClickAction: widgetData.leftClickAction !== undefined ? widgetData.leftClickAction : (widgetMetadata.leftClickAction || "focus")
  property string valueMiddleClickAction: widgetData.middleClickAction !== undefined ? widgetData.middleClickAction : (widgetMetadata.middleClickAction || "none")
  property string valueRightClickAction: widgetData.rightClickAction !== undefined ? widgetData.rightClickAction : (widgetMetadata.rightClickAction || "context-menu")

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
    settings.smartWidth = valueSmartWidth;
    settings.maxTaskbarWidth = valueMaxTaskbarWidth;
    settings.titleWidth = parseInt(titleWidthInput.text) || widgetMetadata.titleWidth;
    settings.showPinnedApps = valueShowPinnedApps;
    settings.iconScale = valueIconScale;
    settings.leftClickAction = valueLeftClickAction;
    settings.middleClickAction = valueMiddleClickAction;
    settings.rightClickAction = valueRightClickAction;
    return settings;
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.hide-mode-label")
    description: I18n.tr("bar.taskbar.hide-mode-description")
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
    onSelected: key => root.valueHideMode = key
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.only-same-monitor-label")
    description: I18n.tr("bar.taskbar.only-same-monitor-description")
    checked: root.valueOnlySameOutput
    onToggled: checked => root.valueOnlySameOutput = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.only-active-workspaces-label")
    description: I18n.tr("bar.taskbar.only-active-workspaces-description")
    checked: root.valueOnlyActiveWorkspaces
    onToggled: checked => root.valueOnlyActiveWorkspaces = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.tray.colorize-icons-label")
    description: I18n.tr("bar.taskbar.colorize-icons-description")
    checked: root.valueColorizeIcons
    onToggled: checked => root.valueColorizeIcons = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.show-pinned-apps-label")
    description: I18n.tr("bar.taskbar.show-pinned-apps-description")
    checked: root.valueShowPinnedApps
    onToggled: checked => root.valueShowPinnedApps = checked
  }

  NDivider {
    Layout.fillWidth: true
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    property var clickActionModel: [
      {
        "key": "none",
        "name": I18n.tr("common.none")
      },
      {
        "key": "focus",
        "name": I18n.tr("actions.focus-activate-window")
      },
      {
        "key": "context-menu",
        "name": I18n.tr("actions.open-context-menu")
      }
    ]

    NComboBox {
      Layout.fillWidth: true
      label: I18n.tr("bar.taskbar.left-click-action-label")
      description: I18n.tr("bar.taskbar.click-action-description")
      model: parent.clickActionModel
      currentKey: root.valueLeftClickAction
      onSelected: key => root.valueLeftClickAction = key
    }
    NComboBox {
      Layout.fillWidth: true
      label: I18n.tr("bar.taskbar.middle-click-action-label")
      description: I18n.tr("bar.taskbar.click-action-description")
      model: parent.clickActionModel
      currentKey: root.valueMiddleClickAction
      onSelected: key => root.valueMiddleClickAction = key
    }
    NComboBox {
      Layout.fillWidth: true
      label: I18n.tr("bar.taskbar.right-click-action-label")
      description: I18n.tr("bar.taskbar.click-action-description")
      model: parent.clickActionModel
      currentKey: root.valueRightClickAction
      onSelected: key => root.valueRightClickAction = key
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("bar.taskbar.icon-scale-label")
      description: I18n.tr("bar.taskbar.icon-scale-description")
    }

    NValueSlider {
      Layout.fillWidth: true
      from: 0.5
      to: 1
      stepSize: 0.01
      value: root.valueIconScale
      onMoved: value => root.valueIconScale = value
      text: Math.round(root.valueIconScale * 100) + "%"
    }
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.show-title-label")
    description: isVerticalBar ? I18n.tr("bar.taskbar.show-title-description-disabled") : I18n.tr("bar.taskbar.show-title-description")
    checked: root.valueShowTitle
    onToggled: checked => root.valueShowTitle = checked
    enabled: !isVerticalBar
  }

  NToggle {
    Layout.fillWidth: true
    visible: !isVerticalBar && root.valueShowTitle
    label: I18n.tr("bar.taskbar.smart-width-label")
    description: I18n.tr("bar.taskbar.smart-width-description")
    checked: root.valueSmartWidth
    onToggled: checked => root.valueSmartWidth = checked
  }

  ColumnLayout {
    visible: root.valueSmartWidth && !isVerticalBar
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("bar.taskbar.max-width-label")
      description: I18n.tr("bar.taskbar.max-width-description")
    }

    NValueSlider {
      Layout.fillWidth: true
      from: 10
      to: 100
      stepSize: 5
      value: root.valueMaxTaskbarWidth
      onMoved: value => root.valueMaxTaskbarWidth = Math.round(value)
      text: Math.round(root.valueMaxTaskbarWidth) + "%"
    }
  }

  NTextInput {
    id: titleWidthInput
    visible: root.valueShowTitle && !isVerticalBar && !root.valueSmartWidth
    Layout.fillWidth: true
    label: I18n.tr("bar.taskbar.title-width-label")
    description: I18n.tr("bar.taskbar.title-width-description")
    text: widgetData.titleWidth || widgetMetadata.titleWidth
    placeholderText: I18n.tr("placeholders.enter-width-pixels")
  }
}
