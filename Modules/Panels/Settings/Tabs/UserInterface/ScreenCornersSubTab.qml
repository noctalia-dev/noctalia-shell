import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NHeader {
    label: I18n.tr("settings.general.screen-corners.section.label")
    description: I18n.tr("settings.general.screen-corners.section.description")
  }

  NToggle {
    label: I18n.tr("settings.general.screen-corners.show-corners.label")
    description: I18n.tr("settings.general.screen-corners.show-corners.description")
    checked: Settings.data.general.showScreenCorners
    isSettings: true
    defaultValue: Settings.getDefaultValue("general.showScreenCorners")
    onToggled: checked => Settings.data.general.showScreenCorners = checked
  }

  NToggle {
    label: I18n.tr("settings.general.screen-corners.solid-black.label")
    description: I18n.tr("settings.general.screen-corners.solid-black.description")
    checked: Settings.data.general.forceBlackScreenCorners
    isSettings: true
    defaultValue: Settings.getDefaultValue("general.forceBlackScreenCorners")
    onToggled: checked => Settings.data.general.forceBlackScreenCorners = checked
  }

  ColumnLayout {
    spacing: Style.marginXXS
    Layout.fillWidth: true

    RowLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("settings.general.screen-corners.radius.label")
        description: I18n.tr("settings.general.screen-corners.radius.description")
        from: 0
        to: 2
        stepSize: 0.01
        value: Settings.data.general.screenRadiusRatio
        isSettings: true
        defaultValue: Settings.getDefaultValue("general.screenRadiusRatio")
        onMoved: value => Settings.data.general.screenRadiusRatio = value
        text: Math.floor(Settings.data.general.screenRadiusRatio * 100) + "%"
      }

      Item {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio

        NIconButton {
          icon: "restore"
          baseSize: Style.baseWidgetSize * 0.8
          tooltipText: I18n.tr("settings.general.screen-corners.radius.reset")
          onClicked: Settings.data.general.screenRadiusRatio = 1.0
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
