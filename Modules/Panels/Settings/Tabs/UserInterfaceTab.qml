import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  // User Interface
  ColumnLayout {
    spacing: Style.marginL
    Layout.fillWidth: true

    NHeader {
      label: I18n.tr("settings.user-interface.section.label")
      description: I18n.tr("settings.user-interface.section.description")
    }

    // Panels attached to bar and screen edges
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

    // Settings panel display mode
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

    // Panel Background Opacity
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

    // Dim desktop opacity
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

    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginL
      Layout.bottomMargin: Style.marginL
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

    // Shadow direction
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
      Layout.topMargin: Style.marginL
      Layout.bottomMargin: Style.marginL
    }

    // User Interface Scaling
    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

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

        // Reset button container
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
    }

    // Container Border Radius
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

      // Reset button container
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

    // Control Border Radius (for UI components)
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

      // Reset button container
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

    // Animation Speed
    ColumnLayout {
      spacing: Style.marginL
      Layout.fillWidth: true

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

          // Reset button container
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

      NToggle {
        label: I18n.tr("settings.user-interface.animation-disable.label")
        description: I18n.tr("settings.user-interface.animation-disable.description")
        checked: Settings.data.general.animationDisabled
        isSettings: true
        defaultValue: Settings.getDefaultValue("general.animationDisabled")
        onToggled: checked => Settings.data.general.animationDisabled = checked
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }

  // Dock
  ColumnLayout {
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

        // Reset button container
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

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginL
    Layout.bottomMargin: Style.marginL
  }
}
