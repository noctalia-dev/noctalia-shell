import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL * scaling

  NHeader {
    label: I18n.tr("settings.launcher.settings.section.label")
    description: I18n.tr("settings.launcher.settings.section.description")
  }

  NComboBox {
    id: launcherPosition
    label: I18n.tr("settings.launcher.settings.position.label")
    description: I18n.tr("settings.launcher.settings.position.description")
    Layout.fillWidth: true
    model: [{
        "key": "center",
        "name": I18n.tr("options.launcher.position.center")
      }, {
        "key": "top_left",
        "name": I18n.tr("options.launcher.position.top_left")
      }, {
        "key": "top_right",
        "name": I18n.tr("options.launcher.position.top_right")
      }, {
        "key": "bottom_left",
        "name": I18n.tr("options.launcher.position.bottom_left")
      }, {
        "key": "bottom_right",
        "name": I18n.tr("options.launcher.position.bottom_right")
      }, {
        "key": "bottom_center",
        "name": I18n.tr("options.launcher.position.bottom_center")
      }, {
        "key": "top_center",
        "name": I18n.tr("options.launcher.position.top_center")
      }]
    currentKey: Settings.data.appLauncher.position
    onSelected: function (key) {
      Settings.data.appLauncher.position = key
    }
  }

  ColumnLayout {
    spacing: Style.marginXXS * scaling
    Layout.fillWidth: true

    NText {
      text: I18n.tr("settings.launcher.settings.background-opacity.label")
      font.pointSize: Style.fontSizeL * scaling
      font.weight: Style.fontWeightBold
      color: Color.mOnSurface
    }

    NText {
      text: I18n.tr("settings.launcher.settings.background-opacity.description")
      font.pointSize: Style.fontSizeXS * scaling
      color: Color.mOnSurfaceVariant
      wrapMode: Text.WordWrap
      Layout.fillWidth: true
    }

    NValueSlider {
      id: launcherBgOpacity
      Layout.fillWidth: true
      from: 0.0
      to: 1.0
      stepSize: 0.01
      value: Settings.data.appLauncher.backgroundOpacity
      onMoved: value => Settings.data.appLauncher.backgroundOpacity = value
      text: Math.floor(Settings.data.appLauncher.backgroundOpacity * 100) + "%"
    }
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.clipboard-history.label")
    description: I18n.tr("settings.launcher.settings.clipboard-history.description")
    checked: Settings.data.appLauncher.enableClipboardHistory
    onToggled: checked => Settings.data.appLauncher.enableClipboardHistory = checked
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.sort-by-usage.label")
    description: I18n.tr("settings.launcher.settings.sort-by-usage.description")
    checked: Settings.data.appLauncher.sortByMostUsed
    onToggled: checked => Settings.data.appLauncher.sortByMostUsed = checked
  }

  NToggle {
    label: I18n.tr("settings.launcher.settings.use-app2unit.label")
    description: I18n.tr("settings.launcher.settings.use-app2unit.description")
    checked: Settings.data.appLauncher.useApp2Unit
    onToggled: checked => Settings.data.appLauncher.useApp2Unit = checked
  }

  NTextInput {
    label: I18n.tr("settings.launcher.settings.terminal-command.label")
    description: I18n.tr("settings.launcher.settings.terminal-command.description")
    Layout.fillWidth: true
    text: Settings.data.appLauncher.terminalCommand
    onEditingFinished: {
      Settings.data.appLauncher.terminalCommand = text
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL * scaling
    Layout.bottomMargin: Style.marginXL * scaling
  }
}
