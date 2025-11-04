import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
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

    NToggle {
      label: I18n.tr("settings.user-interface.tooltips.label")
      description: I18n.tr("settings.user-interface.tooltips.description")
      checked: Settings.data.ui.tooltipsEnabled
      onToggled: checked => Settings.data.ui.tooltipsEnabled = checked
    }

    NToggle {
      label: I18n.tr("settings.user-interface.dim-desktop.label")
      description: I18n.tr("settings.user-interface.dim-desktop.description")
      checked: Settings.data.general.dimDesktop
      onToggled: checked => Settings.data.general.dimDesktop = checked
    }

    NToggle {
      label: I18n.tr("settings.user-interface.panels-attached-to-bar.label")
      description: I18n.tr("settings.user-interface.panels-attached-to-bar.description")
      checked: Settings.data.ui.panelsAttachedToBar
      onToggled: checked => Settings.data.ui.panelsAttachedToBar = checked
    }

    NToggle {
      label: I18n.tr("settings.user-interface.shadows.label")
      description: I18n.tr("settings.user-interface.shadows.description")
      checked: Settings.data.general.enableShadows
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
        }
      })

      currentKey: Settings.data.general.shadowDirection

      onSelected: function (key) {
        var opt = shadowOptionsMap[key]
        if (opt) {
          Settings.data.general.shadowDirection = key
          Settings.data.general.shadowOffsetX = opt.p.x
          Settings.data.general.shadowOffsetY = opt.p.y
        }
      }
    }

    NToggle {
      label: I18n.tr("settings.user-interface.panels-overlay.label")
      description: I18n.tr("settings.user-interface.panels-overlay.description")
      checked: Settings.data.ui.panelsOverlayLayer
      onToggled: checked => Settings.data.ui.panelsOverlayLayer = checked
    }

    NDivider {
      Layout.fillWidth: true
      Layout.topMargin: Style.marginL
      Layout.bottomMargin: Style.marginL
    }

    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.user-interface.scaling.label")
        description: I18n.tr("settings.user-interface.scaling.description")
      }

      RowLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

        NValueSlider {
          Layout.fillWidth: true
          from: 0.8
          to: 1.2
          stepSize: 0.05
          value: Settings.data.general.scaleRatio
          onMoved: value => Settings.data.general.scaleRatio = value
          text: Math.floor(Settings.data.general.scaleRatio * 100) + "%"
        }

        // Reset button container
        Item {
          Layout.preferredWidth: 30 * Style.uiScaleRatio
          Layout.preferredHeight: 30 * Style.uiScaleRatio

          NIconButton {
            icon: "refresh"
            baseSize: Style.baseWidgetSize * 0.8
            tooltipText: I18n.tr("settings.user-interface.scaling.reset-scaling")
            onClicked: Settings.data.general.scaleRatio = 1.0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }

    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.user-interface.border-radius.label")
        description: I18n.tr("settings.user-interface.border-radius.description")
      }

      RowLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

        NValueSlider {
          Layout.fillWidth: true
          from: 0
          to: 2
          stepSize: 0.01
          value: Settings.data.general.radiusRatio
          onMoved: value => Settings.data.general.radiusRatio = value
          text: Math.floor(Settings.data.general.radiusRatio * 100) + "%"
        }

        // Reset button container
        Item {
          Layout.preferredWidth: 30 * Style.uiScaleRatio
          Layout.preferredHeight: 30 * Style.uiScaleRatio

          NIconButton {
            icon: "refresh"
            baseSize: Style.baseWidgetSize * 0.8
            tooltipText: I18n.tr("settings.user-interface.border-radius.reset")
            onClicked: Settings.data.general.radiusRatio = 1.0
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
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

        NLabel {
          label: I18n.tr("settings.user-interface.animation-speed.label")
          description: I18n.tr("settings.user-interface.animation-speed.description")
        }

        RowLayout {
          spacing: Style.marginL
          Layout.fillWidth: true

          NValueSlider {
            Layout.fillWidth: true
            from: 0.1
            to: 2.0
            stepSize: 0.01
            value: Settings.data.general.animationSpeed
            onMoved: value => Settings.data.general.animationSpeed = value
            text: Math.round(Settings.data.general.animationSpeed * 100) + "%"
          }

          // Reset button container
          Item {
            Layout.preferredWidth: 30 * Style.uiScaleRatio
            Layout.preferredHeight: 30 * Style.uiScaleRatio

            NIconButton {
              icon: "refresh"
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
        onToggled: checked => Settings.data.general.animationDisabled = checked
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
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
      onToggled: checked => Settings.data.general.showScreenCorners = checked
    }

    NToggle {
      label: I18n.tr("settings.general.screen-corners.solid-black.label")
      description: I18n.tr("settings.general.screen-corners.solid-black.description")
      checked: Settings.data.general.forceBlackScreenCorners
      onToggled: checked => Settings.data.general.forceBlackScreenCorners = checked
    }

    ColumnLayout {
      spacing: Style.marginXXS
      Layout.fillWidth: true

      NLabel {
        label: I18n.tr("settings.general.screen-corners.radius.label")
        description: I18n.tr("settings.general.screen-corners.radius.description")
      }

      RowLayout {
        spacing: Style.marginL
        Layout.fillWidth: true

        NValueSlider {
          Layout.fillWidth: true
          from: 0
          to: 2
          stepSize: 0.01
          value: Settings.data.general.screenRadiusRatio
          onMoved: value => Settings.data.general.screenRadiusRatio = value
          text: Math.floor(Settings.data.general.screenRadiusRatio * 100) + "%"
        }

        // Reset button container
        Item {
          Layout.preferredWidth: 30 * Style.uiScaleRatio
          Layout.preferredHeight: 30 * Style.uiScaleRatio

          NIconButton {
            icon: "refresh"
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
    Layout.topMargin: Style.marginXL
    Layout.bottomMargin: Style.marginXL
  }
}
