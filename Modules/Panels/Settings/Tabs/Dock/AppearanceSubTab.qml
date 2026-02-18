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
    Layout.fillWidth: true
    label: I18n.tr("panels.dock.enabled-label")
    description: I18n.tr("panels.dock.enabled-description")
    checked: Settings.data.dock.enabled
    defaultValue: Settings.getDefaultValue("dock.enabled")
    onToggled: checked => Settings.data.dock.enabled = checked
  }

  ColumnLayout {
    spacing: Style.marginL
    enabled: Settings.data.dock.enabled

    NComboBox {
      Layout.fillWidth: true
      label: I18n.tr("panels.dock.appearance-position-label")
      description: I18n.tr("panels.dock.appearance-position-description")
      model: [
        {
          "key": "top",
          "name": I18n.tr("positions.top")
        },
        {
          "key": "bottom",
          "name": I18n.tr("positions.bottom")
        },
        {
          "key": "left",
          "name": I18n.tr("positions.left")
        },
        {
          "key": "right",
          "name": I18n.tr("positions.right")
        }
      ]
      currentKey: Settings.data.dock.position
      defaultValue: Settings.getDefaultValue("dock.position")
      onSelected: key => Settings.data.dock.position = key
    }

    NComboBox {
      Layout.fillWidth: true
      label: I18n.tr("panels.dock.appearance-type-label")
      description: I18n.tr("panels.dock.appearance-type-description")
      model: [
        {
          "key": "floating",
          "name": I18n.tr("panels.dock.appearance-type-floating")
        },
        {
          "key": "static",
          "name": I18n.tr("panels.dock.appearance-type-static")
        }
      ]
      currentKey: Settings.data.dock.dockType
      defaultValue: Settings.getDefaultValue("dock.dockType")
      onSelected: key => Settings.data.dock.dockType = key
    }

    NComboBox {
      visible: Settings.data.dock.dockType === "floating"
      Layout.fillWidth: true
      label: I18n.tr("panels.display.title")
      description: I18n.tr("panels.dock.appearance-display-description")
      model: [
        {
          "key": "always_visible",
          "name": I18n.tr("hide-modes.visible")
        },
        {
          "key": "auto_hide",
          "name": I18n.tr("panels.dock.appearance-display-auto-hide")
        },
        {
          "key": "exclusive",
          "name": I18n.tr("panels.dock.appearance-display-exclusive")
        }
      ]
      currentKey: Settings.data.dock.displayMode
      defaultValue: Settings.getDefaultValue("dock.displayMode")
      onSelected: key => {
                    Settings.data.dock.displayMode = key;
                  }
    }

    NToggle {
      Layout.fillWidth: true
      visible: Settings.data.dock.dockType === "static" && Settings.data.bar.barType === "framed"
      label: I18n.tr("panels.dock.appearance-sit-on-frame-label")
      description: I18n.tr("panels.dock.appearance-sit-on-frame-description")
      checked: Settings.data.dock.sitOnFrame
      defaultValue: Settings.getDefaultValue("dock.sitOnFrame")
      onToggled: checked => Settings.data.dock.sitOnFrame = checked
    }

    NToggle {
      Layout.fillWidth: true
      visible: Settings.data.dock.dockType === "static" && Settings.data.bar.barType === "framed"
      label: I18n.tr("panels.dock.appearance-frame-indicator-label")
      description: I18n.tr("panels.dock.appearance-frame-indicator-description")
      checked: Settings.data.dock.showFrameIndicator
      defaultValue: Settings.getDefaultValue("dock.showFrameIndicator")
      onToggled: checked => Settings.data.dock.showFrameIndicator = checked
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.osd.background-opacity-label")
      description: I18n.tr("panels.dock.appearance-background-opacity-description")
      from: 0
      to: 1
      stepSize: 0.01
      showReset: true
      value: Settings.data.dock.backgroundOpacity
      defaultValue: Settings.getDefaultValue("dock.backgroundOpacity")
      onMoved: value => Settings.data.dock.backgroundOpacity = value
      text: Math.floor(Settings.data.dock.backgroundOpacity * 100) + "%"
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.dock.appearance-dead-opacity-label")
      description: I18n.tr("panels.dock.appearance-dead-opacity-description")
      from: 0
      to: 1
      stepSize: 0.01
      showReset: true
      value: Settings.data.dock.deadOpacity
      defaultValue: Settings.getDefaultValue("dock.deadOpacity")
      onMoved: value => Settings.data.dock.deadOpacity = value
      text: Math.floor(Settings.data.dock.deadOpacity * 100) + "%"
    }

    NValueSlider {
      Layout.fillWidth: true
      visible: Settings.data.dock.dockType === "floating"
      label: I18n.tr("panels.dock.appearance-floating-distance-label")
      description: I18n.tr("panels.dock.appearance-floating-distance-description")
      from: 0
      to: 4
      stepSize: 0.01
      showReset: true
      value: Settings.data.dock.floatingRatio
      defaultValue: Settings.getDefaultValue("dock.floatingRatio")
      onMoved: value => Settings.data.dock.floatingRatio = value
      text: Math.floor(Settings.data.dock.floatingRatio * 100) + "%"
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.dock.appearance-icon-size-label")
      description: I18n.tr("panels.dock.appearance-icon-size-description")
      from: 0
      to: 2
      stepSize: 0.01
      showReset: true
      value: Settings.data.dock.size
      defaultValue: Settings.getDefaultValue("dock.size")
      onMoved: value => Settings.data.dock.size = value
      text: Math.floor(Settings.data.dock.size * 100) + "%"
    }

    NValueSlider {
      visible: Settings.data.dock.dockType === "floating" && Settings.data.dock.displayMode === "auto_hide"
      Layout.fillWidth: true
      label: I18n.tr("panels.dock.appearance-hide-show-speed-label")
      description: I18n.tr("panels.dock.appearance-hide-show-speed-description")
      from: 0.1
      to: 2.0
      stepSize: 0.01
      showReset: true
      value: Settings.data.dock.animationSpeed
      defaultValue: Settings.getDefaultValue("dock.animationSpeed")
      onMoved: value => Settings.data.dock.animationSpeed = value
      text: (Settings.data.dock.animationSpeed * 100).toFixed(0) + "%"
    }

    NToggle {
      label: I18n.tr("panels.dock.appearance-inactive-indicators-label")
      description: I18n.tr("panels.dock.appearance-inactive-indicators-description")
      checked: Settings.data.dock.inactiveIndicators
      defaultValue: Settings.getDefaultValue("dock.inactiveIndicators")
      onToggled: checked => Settings.data.dock.inactiveIndicators = checked
    }

    NToggle {
      label: I18n.tr("panels.dock.appearance-pinned-static-label")
      description: I18n.tr("panels.dock.appearance-pinned-static-description")
      checked: Settings.data.dock.pinnedStatic
      defaultValue: Settings.getDefaultValue("dock.pinnedStatic")
      onToggled: checked => Settings.data.dock.pinnedStatic = checked
    }

    NToggle {
      label: I18n.tr("panels.dock.monitors-only-same-monitor-label")
      description: I18n.tr("panels.dock.monitors-only-same-monitor-description")
      checked: Settings.data.dock.onlySameOutput
      defaultValue: Settings.getDefaultValue("dock.onlySameOutput")
      onToggled: checked => Settings.data.dock.onlySameOutput = checked
    }

    NToggle {
      Layout.fillWidth: true
      label: I18n.tr("panels.dock.appearance-colorize-icons-label")
      description: I18n.tr("panels.dock.appearance-colorize-icons-description")
      checked: Settings.data.dock.colorizeIcons
      defaultValue: Settings.getDefaultValue("dock.colorizeIcons")
      onToggled: checked => Settings.data.dock.colorizeIcons = checked
    }
  }
}
