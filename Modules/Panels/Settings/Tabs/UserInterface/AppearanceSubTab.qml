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
    label: I18n.tr("settings.user-interface.appearance.section.label")
    description: I18n.tr("settings.user-interface.appearance.section.description")
  }

  NToggle {
    label: I18n.tr("settings.user-interface.tooltips.label")
    description: I18n.tr("settings.user-interface.tooltips.description")
    checked: Settings.data.ui.tooltipsEnabled
    isSettings: true
    defaultValue: Settings.getDefaultValue("ui.tooltipsEnabled")
    onToggled: checked => Settings.data.ui.tooltipsEnabled = checked
  }

  NToggle {
    label: I18n.tr("settings.user-interface.box-border.label")
    description: I18n.tr("settings.user-interface.box-border.description")
    checked: Settings.data.ui.boxBorderEnabled
    isSettings: true
    defaultValue: Settings.getDefaultValue("ui.boxBorderEnabled")
    onToggled: checked => Settings.data.ui.boxBorderEnabled = checked
  }

  NToggle {
    label: I18n.tr("settings.user-interface.shadows.label")
    description: I18n.tr("settings.user-interface.shadows.description")
    checked: Settings.data.general.enableShadows
    isSettings: true
    defaultValue: Settings.getDefaultValue("general.enableShadows")
    onToggled: checked => Settings.data.general.enableShadows = checked
  }

  NComboBox {
    visible: Settings.data.general.enableShadows
    label: I18n.tr("settings.user-interface.shadows.direction.label")
    description: I18n.tr("settings.user-interface.shadows.direction.description")
    Layout.fillWidth: true

    readonly property var shadowOptionsMap: ({
                                               "top_left": {
                                                 "name": I18n.tr("options.shadow-direction.top_left"),
                                                 "p": Qt.point(-2, -2)
                                               },
                                               "top": {
                                                 "name": I18n.tr("options.shadow-direction.top"),
                                                 "p": Qt.point(0, -3)
                                               },
                                               "top_right": {
                                                 "name": I18n.tr("options.shadow-direction.top_right"),
                                                 "p": Qt.point(2, -2)
                                               },
                                               "left": {
                                                 "name": I18n.tr("options.shadow-direction.left"),
                                                 "p": Qt.point(-3, 0)
                                               },
                                               "center": {
                                                 "name": I18n.tr("options.shadow-direction.center"),
                                                 "p": Qt.point(0, 0)
                                               },
                                               "right": {
                                                 "name": I18n.tr("options.shadow-direction.right"),
                                                 "p": Qt.point(3, 0)
                                               },
                                               "bottom_left": {
                                                 "name": I18n.tr("options.shadow-direction.bottom_left"),
                                                 "p": Qt.point(-2, 2)
                                               },
                                               "bottom": {
                                                 "name": I18n.tr("options.shadow-direction.bottom"),
                                                 "p": Qt.point(0, 3)
                                               },
                                               "bottom_right": {
                                                 "name": I18n.tr("options.shadow-direction.bottom_right"),
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
    isSettings: true
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

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.user-interface.scaling.label")
      description: I18n.tr("settings.user-interface.scaling.description")
      from: 0.8
      to: 1.2
      stepSize: 0.05
      value: Settings.data.general.scaleRatio
      isSettings: true
      defaultValue: Settings.getDefaultValue("general.scaleRatio")
      onMoved: value => Settings.data.general.scaleRatio = value
      text: Math.floor(Settings.data.general.scaleRatio * 100) + "%"
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("settings.user-interface.scaling.reset-scaling")
        onClicked: Settings.data.general.scaleRatio = 1.0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.user-interface.box-border-radius.label")
      description: I18n.tr("settings.user-interface.box-border-radius.description")
      from: 0
      to: 2
      stepSize: 0.01
      value: Settings.data.general.radiusRatio
      isSettings: true
      defaultValue: Settings.getDefaultValue("general.radiusRatio")
      onMoved: value => Settings.data.general.radiusRatio = value
      text: Math.floor(Settings.data.general.radiusRatio * 100) + "%"
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("settings.user-interface.box-border-radius.reset")
        onClicked: Settings.data.general.radiusRatio = 1.0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  RowLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("settings.user-interface.control-border-radius.label")
      description: I18n.tr("settings.user-interface.control-border-radius.description")
      from: 0
      to: 2
      stepSize: 0.01
      value: Settings.data.general.iRadiusRatio
      isSettings: true
      defaultValue: Settings.getDefaultValue("general.iRadiusRatio")
      onMoved: value => Settings.data.general.iRadiusRatio = value
      text: Math.floor(Settings.data.general.iRadiusRatio * 100) + "%"
    }

    Item {
      Layout.preferredWidth: 30 * Style.uiScaleRatio
      Layout.preferredHeight: 30 * Style.uiScaleRatio

      NIconButton {
        icon: "restore"
        baseSize: Style.baseWidgetSize * 0.8
        tooltipText: I18n.tr("settings.user-interface.control-border-radius.reset")
        onClicked: Settings.data.general.iRadiusRatio = 1.0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
  }

  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NToggle {
      label: I18n.tr("settings.user-interface.animation-disable.label")
      description: I18n.tr("settings.user-interface.animation-disable.description")
      checked: Settings.data.general.animationDisabled
      isSettings: true
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
          label: I18n.tr("settings.user-interface.animation-speed.label")
          description: I18n.tr("settings.user-interface.animation-speed.description")
          from: 0
          to: 2.0
          stepSize: 0.01
          value: Settings.data.general.animationSpeed
          isSettings: true
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
            tooltipText: I18n.tr("settings.user-interface.animation-speed.reset")
            onClicked: Settings.data.general.animationSpeed = 1.0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }
}
