import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.user-interface.section.label")
    description: I18n.tr("settings.user-interface.section.description")
  }

  NToggle {
    label: I18n.tr("settings.user-interface.panels-attached-to-bar.label")
    description: I18n.tr("settings.user-interface.panels-attached-to-bar.description")
    checked: Settings.data.ui.panelsAttachedToBar
    isSettings: true
    defaultValue: Settings.getDefaultValue("ui.panelsAttachedToBar")
    onToggled: checked => Settings.data.ui.panelsAttachedToBar = checked
  }

  NToggle {
    visible: (Quickshell.screens.length > 1)
    label: I18n.tr("settings.user-interface.allow-panels-without-bar.label")
    description: I18n.tr("settings.user-interface.allow-panels-without-bar.description")
    checked: Settings.data.general.allowPanelsOnScreenWithoutBar
    isSettings: true
    defaultValue: Settings.getDefaultValue("general.allowPanelsOnScreenWithoutBar")
    onToggled: checked => Settings.data.general.allowPanelsOnScreenWithoutBar = checked
  }

  NComboBox {
    label: I18n.tr("settings.user-interface.settings-panel-mode.label")
    description: I18n.tr("settings.user-interface.settings-panel-mode.description")
    Layout.fillWidth: true
    model: [
      {
        "key": "attached",
        "name": I18n.tr("options.settings-panel-mode.attached")
      },
      {
        "key": "centered",
        "name": I18n.tr("options.settings-panel-mode.centered")
      },
      {
        "key": "window",
        "name": I18n.tr("options.settings-panel-mode.window")
      }
    ]
    currentKey: Settings.data.ui.settingsPanelMode
    isSettings: true
    defaultValue: Settings.getDefaultValue("ui.settingsPanelMode")
    onSelected: key => Settings.data.ui.settingsPanelMode = key
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("settings.user-interface.panel-background-opacity.label")
    description: I18n.tr("settings.user-interface.panel-background-opacity.description")
    from: 0.4
    to: 1
    stepSize: 0.01
    value: Settings.data.ui.panelBackgroundOpacity
    isSettings: true
    defaultValue: Settings.getDefaultValue("ui.panelBackgroundOpacity")
    onMoved: value => Settings.data.ui.panelBackgroundOpacity = value
    text: Math.floor(Settings.data.ui.panelBackgroundOpacity * 100) + "%"
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("settings.user-interface.dimmer-opacity.label")
    description: I18n.tr("settings.user-interface.dimmer-opacity.description")
    from: 0
    to: 1
    stepSize: 0.01
    value: Settings.data.general.dimmerOpacity
    isSettings: true
    defaultValue: Settings.getDefaultValue("general.dimmerOpacity")
    onMoved: value => Settings.data.general.dimmerOpacity = value
    text: Math.floor(Settings.data.general.dimmerOpacity * 100) + "%"
  }
}
