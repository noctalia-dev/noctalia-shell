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
    label: I18n.tr("panels.user-interface.tooltips-label")
    description: I18n.tr("panels.user-interface.tooltips-description")
    checked: Settings.data.ui.tooltipsEnabled
    defaultValue: Settings.getDefaultValue("ui.tooltipsEnabled")
    onToggled: checked => Settings.data.ui.tooltipsEnabled = checked
  }

  NToggle {
    label: I18n.tr("panels.user-interface.box-border-label")
    description: I18n.tr("panels.user-interface.box-border-description")
    checked: Settings.data.ui.boxBorderEnabled
    defaultValue: Settings.getDefaultValue("ui.boxBorderEnabled")
    onToggled: checked => Settings.data.ui.boxBorderEnabled = checked
  }

  NToggle {
    label: I18n.tr("panels.user-interface.shadows-label")
    description: I18n.tr("panels.user-interface.shadows-description")
    checked: Settings.data.general.enableShadows
    defaultValue: Settings.getDefaultValue("general.enableShadows")
    onToggled: checked => Settings.data.general.enableShadows = checked
  }

  NComboBox {
    visible: Settings.data.general.enableShadows
    label: I18n.tr("panels.user-interface.shadows-direction-label")
    description: I18n.tr("panels.user-interface.shadows-direction-description")
    Layout.fillWidth: true

    readonly property var shadowOptionsMap: ({
                                               "top_left": {
                                                 "name": I18n.tr("positions.top-left"),
                                                 "p": Qt.point(-2, -2)
                                               },
                                               "top": {
                                                 "name": I18n.tr("positions.top"),
                                                 "p": Qt.point(0, -3)
                                               },
                                               "top_right": {
                                                 "name": I18n.tr("positions.top-right"),
                                                 "p": Qt.point(2, -2)
                                               },
                                               "left": {
                                                 "name": I18n.tr("positions.left"),
                                                 "p": Qt.point(-3, 0)
                                               },
                                               "center": {
                                                 "name": I18n.tr("positions.center"),
                                                 "p": Qt.point(0, 0)
                                               },
                                               "right": {
                                                 "name": I18n.tr("positions.right"),
                                                 "p": Qt.point(3, 0)
                                               },
                                               "bottom_left": {
                                                 "name": I18n.tr("positions.bottom-left"),
                                                 "p": Qt.point(-2, 2)
                                               },
                                               "bottom": {
                                                 "name": I18n.tr("positions.bottom"),
                                                 "p": Qt.point(0, 3)
                                               },
                                               "bottom_right": {
                                                 "name": I18n.tr("positions.bottom-right"),
                                                 "p": Qt.point(2, 3)
                                               }
                                             })

    model: Object.keys(shadowOptionsMap).map(function (k) {
      return {
        "key": k,
        "name": shadowOptionsMap[k].name
      };
    })

    currentKey: Settings.data.general.shadowDirection
    defaultValue: Settings.getDefaultValue("general.shadowDirection")

    onSelected: function (key) {
      var opt = shadowOptionsMap[key];
      if (opt) {
        Settings.data.general.shadowDirection = key;
        Settings.data.general.shadowOffsetX = opt.p.x;
        Settings.data.general.shadowOffsetY = opt.p.y;
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.user-interface.scaling-label")
    description: I18n.tr("panels.user-interface.scaling-description")
    from: 0.8
    to: 1.2
    stepSize: 0.05
    showReset: true
    value: Settings.data.general.scaleRatio
    defaultValue: Settings.getDefaultValue("general.scaleRatio")
    onMoved: value => Settings.data.general.scaleRatio = value
    text: Math.floor(Settings.data.general.scaleRatio * 100) + "%"
  }

  NDivider {
    Layout.fillWidth: true
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.user-interface.box-border-radius-label")
    description: I18n.tr("panels.user-interface.box-border-radius-description")
    from: 0
    to: 2
    stepSize: 0.01
    showReset: true
    value: Settings.data.general.radiusRatio
    defaultValue: Settings.getDefaultValue("general.radiusRatio")
    onMoved: value => Settings.data.general.radiusRatio = value
    text: Math.floor(Settings.data.general.radiusRatio * 100) + "%"
  }

  NValueSlider {
    Layout.fillWidth: true
    label: I18n.tr("panels.user-interface.control-border-radius-label")
    description: I18n.tr("panels.user-interface.control-border-radius-description")
    from: 0
    to: 2
    stepSize: 0.01
    showReset: true
    value: Settings.data.general.iRadiusRatio
    defaultValue: Settings.getDefaultValue("general.iRadiusRatio")
    onMoved: value => Settings.data.general.iRadiusRatio = value
    text: Math.floor(Settings.data.general.iRadiusRatio * 100) + "%"
  }

  NDivider {
    Layout.fillWidth: true
  }

  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NToggle {
      label: I18n.tr("panels.user-interface.animation-disable-label")
      description: I18n.tr("panels.user-interface.animation-disable-description")
      checked: Settings.data.general.animationDisabled
      defaultValue: Settings.getDefaultValue("general.animationDisabled")
      onToggled: checked => Settings.data.general.animationDisabled = checked
    }

    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true
      visible: !Settings.data.general.animationDisabled

      RowLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

        NValueSlider {
          Layout.fillWidth: true
          label: I18n.tr("panels.user-interface.animation-speed-label")
          description: I18n.tr("panels.user-interface.animation-speed-description")
          from: 0
          to: 2.0
          stepSize: 0.01
          value: Settings.data.general.animationSpeed
          defaultValue: Settings.getDefaultValue("general.animationSpeed")
          onMoved: value => Settings.data.general.animationSpeed = Math.max(value, 0.05)
          text: Math.round(Settings.data.general.animationSpeed * 100) + "%"
        }

        Item {
          Layout.preferredWidth: 30 * Style.uiScaleRatio
          Layout.preferredHeight: 30 * Style.uiScaleRatio

          NIconButton {
            icon: "restore"
            baseSize: Style.baseWidgetSize * 0.8
            tooltipText: I18n.tr("panels.user-interface.animation-speed-reset")
            onClicked: Settings.data.general.animationSpeed = Settings.getDefaultValue("general.animationSpeed")
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }
}
