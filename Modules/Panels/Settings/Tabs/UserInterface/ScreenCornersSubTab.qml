import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NToggle {
    label: I18n.tr("panels.general.screen-corners-show-corners-label")
    description: I18n.tr("panels.general.screen-corners-show-corners-description")
    checked: Settings.data.general.showScreenCorners
    defaultValue: Settings.getDefaultValue("general.showScreenCorners")
    onToggled: checked => Settings.data.general.showScreenCorners = checked
  }

  NToggle {
    label: I18n.tr("panels.general.screen-corners-solid-black-label")
    description: I18n.tr("panels.general.screen-corners-solid-black-description")
    checked: Settings.data.general.forceBlackScreenCorners
    defaultValue: Settings.getDefaultValue("general.forceBlackScreenCorners")
    onToggled: checked => Settings.data.general.forceBlackScreenCorners = checked
  }

  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.general.screen-corners-radius-label")
      description: I18n.tr("panels.general.screen-corners-radius-description")
      from: 0
      to: 2
      stepSize: 0.01
      showReset: true
      value: Settings.data.general.screenRadiusRatio
      defaultValue: Settings.getDefaultValue("general.screenRadiusRatio")
      onMoved: value => Settings.data.general.screenRadiusRatio = value
      text: Math.floor(Settings.data.general.screenRadiusRatio * 100) + "%"
    }
  }
}
