import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.Compositor
import qs.Widgets

ColumnLayout {
  id: root
  spacing: Style.marginL
  Layout.fillWidth: true

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.appearance-position-label")
    description: I18n.tr("panels.bar.appearance-position-description")
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
    currentKey: Settings.data.bar.position
    defaultValue: Settings.getDefaultValue("bar.position")
    onSelected: key => Settings.data.bar.position = key
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.appearance-density-label")
    description: I18n.tr("panels.bar.appearance-density-description")
    model: [
      {
        "key": "mini",
        "name": I18n.tr("options.bar.density-mini")
      },
      {
        "key": "compact",
        "name": I18n.tr("options.bar.density-compact")
      },
      {
        "key": "default",
        "name": I18n.tr("options.bar.density-default")
      },
      {
        "key": "comfortable",
        "name": I18n.tr("options.bar.density-comfortable")
      },
      {
        "key": "spacious",
        "name": I18n.tr("options.bar.density-spacious")
      }
    ]
    currentKey: Settings.data.bar.density
    defaultValue: Settings.getDefaultValue("bar.density")
    onSelected: key => Settings.data.bar.density = key
  }
  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.appearance-type-label")
    description: I18n.tr("panels.bar.appearance-type-description")
    model: [
      {
        "key": "simple",
        "name": I18n.tr("options.bar.type-simple")
      },
      {
        "key": "floating",
        "name": I18n.tr("options.bar.type-floating")
      },
      {
        "key": "framed",
        "name": I18n.tr("options.bar.type-framed")
      }
    ]
    currentKey: Settings.data.bar.barType
    defaultValue: Settings.getDefaultValue("bar.barType")
    onSelected: key => {
                  Settings.data.bar.barType = key;
                  Settings.data.bar.floating = (key === "floating");
                }
  }

  NComboBox {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.appearance-display-mode-label")
    description: I18n.tr("panels.bar.appearance-display-mode-description")
    model: [
      {
        "key": "always_visible",
        "name": I18n.tr("hide-modes.visible")
      },
      {
        "key": "auto_hide",
        "name": I18n.tr("hide-modes.auto-hide")
      }
    ]
    currentKey: Settings.data.bar.displayMode
    defaultValue: Settings.getDefaultValue("bar.displayMode")
    onSelected: key => Settings.data.bar.displayMode = key
  }

  NToggle {
    label: I18n.tr("panels.bar.appearance-use-separate-opacity-label")
    description: I18n.tr("panels.bar.appearance-use-separate-opacity-description")
    checked: Settings.data.bar.useSeparateOpacity
    defaultValue: Settings.getDefaultValue("bar.useSeparateOpacity")
    onToggled: checked => Settings.data.bar.useSeparateOpacity = checked
  }

  NValueSlider {
    Layout.fillWidth: true
    visible: Settings.data.bar.useSeparateOpacity
    label: I18n.tr("panels.bar.appearance-background-opacity-label")
    description: I18n.tr("panels.bar.appearance-background-opacity-description")
    from: 0
    to: 1
    stepSize: 0.01
    value: Settings.data.bar.backgroundOpacity
    defaultValue: Settings.getDefaultValue("bar.backgroundOpacity")
    onMoved: value => Settings.data.bar.backgroundOpacity = value
    text: Math.floor(Settings.data.bar.backgroundOpacity * 100) + "%"
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.appearance-show-outline-label")
    description: I18n.tr("panels.bar.appearance-show-outline-description")
    checked: Settings.data.bar.showOutline
    defaultValue: Settings.getDefaultValue("bar.showOutline")
    onToggled: checked => Settings.data.bar.showOutline = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.appearance-show-capsule-label")
    description: I18n.tr("panels.bar.appearance-show-capsule-description")
    checked: Settings.data.bar.showCapsule
    defaultValue: Settings.getDefaultValue("bar.showCapsule")
    onToggled: checked => Settings.data.bar.showCapsule = checked
  }

  NValueSlider {
    Layout.fillWidth: true
    visible: Settings.data.bar.showCapsule
    label: I18n.tr("panels.bar.appearance-capsule-opacity-label")
    description: I18n.tr("panels.bar.appearance-capsule-opacity-description")
    from: 0
    to: 1
    stepSize: 0.01
    value: Settings.data.bar.capsuleOpacity
    defaultValue: Settings.getDefaultValue("bar.capsuleOpacity")
    onMoved: value => Settings.data.bar.capsuleOpacity = value
    text: Math.floor(Settings.data.bar.capsuleOpacity * 100) + "%"
  }

  NToggle {
    Layout.fillWidth: true
    visible: CompositorService.isNiri
    label: I18n.tr("panels.bar.appearance-hide-on-overview-label")
    description: I18n.tr("panels.bar.appearance-hide-on-overview-description")
    checked: Settings.data.bar.hideOnOverview
    defaultValue: Settings.getDefaultValue("bar.hideOnOverview")
    onToggled: checked => Settings.data.bar.hideOnOverview = checked
  }

  NToggle {
    Layout.fillWidth: true
    label: I18n.tr("panels.bar.appearance-outer-corners-label")
    description: I18n.tr("panels.bar.appearance-outer-corners-description")
    checked: Settings.data.bar.outerCorners
    visible: Settings.data.bar.barType === "simple"
    defaultValue: Settings.getDefaultValue("bar.outerCorners")
    onToggled: checked => Settings.data.bar.outerCorners = checked
  }

  ColumnLayout {
    visible: Settings.data.bar.barType === "framed"
    spacing: Style.marginS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("panels.bar.appearance-frame-settings-label")
      description: I18n.tr("panels.bar.appearance-frame-settings-description")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginL

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("panels.bar.appearance-frame-thickness")
        from: 4
        to: 24
        stepSize: 1
        value: Settings.data.bar.frameThickness
        defaultValue: Settings.getDefaultValue("bar.frameThickness")
        onMoved: value => Settings.data.bar.frameThickness = value
        text: Settings.data.bar.frameThickness + "px"
      }

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("panels.bar.appearance-frame-radius")
        from: 4
        to: 24
        stepSize: 1
        value: Settings.data.bar.frameRadius
        defaultValue: Settings.getDefaultValue("bar.frameRadius")
        onMoved: value => Settings.data.bar.frameRadius = value
        text: Settings.data.bar.frameRadius + "px"
      }
    }
  }

  ColumnLayout {
    visible: Settings.data.bar.barType === "floating"
    spacing: Style.marginS
    Layout.fillWidth: true

    NLabel {
      label: I18n.tr("panels.bar.appearance-margins-label")
      description: I18n.tr("panels.bar.appearance-margins-description")
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginL

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("panels.bar.appearance-margins-vertical")
        from: 0
        to: 18
        stepSize: 1
        value: Settings.data.bar.marginVertical
        defaultValue: Settings.getDefaultValue("bar.marginVertical")
        onMoved: value => Settings.data.bar.marginVertical = value
        text: Settings.data.bar.marginVertical + "px"
      }

      NValueSlider {
        Layout.fillWidth: true
        label: I18n.tr("panels.bar.appearance-margins-horizontal")
        from: 0
        to: 18
        stepSize: 1
        value: Settings.data.bar.marginHorizontal
        defaultValue: Settings.getDefaultValue("bar.marginHorizontal")
        onMoved: value => Settings.data.bar.marginHorizontal = value
        text: Settings.data.bar.marginHorizontal + "px"
      }
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginS
  }

  ColumnLayout {
    visible: Settings.data.bar.displayMode === "auto_hide"
    spacing: Style.marginS
    Layout.fillWidth: true

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.bar.appearance-auto-hide-delay-label")
      description: I18n.tr("panels.bar.appearance-auto-hide-delay-description")
      from: 100
      to: 2000
      stepSize: 100
      value: Settings.data.bar.autoHideDelay
      defaultValue: Settings.getDefaultValue("bar.autoHideDelay")
      onMoved: value => Settings.data.bar.autoHideDelay = value
      text: Settings.data.bar.autoHideDelay + "ms"
    }

    NValueSlider {
      Layout.fillWidth: true
      label: I18n.tr("panels.bar.appearance-auto-show-delay-label")
      description: I18n.tr("panels.bar.appearance-auto-show-delay-description")
      from: 0
      to: 500
      stepSize: 50
      value: Settings.data.bar.autoShowDelay
      defaultValue: Settings.getDefaultValue("bar.autoShowDelay")
      onMoved: value => Settings.data.bar.autoShowDelay = value
      text: Settings.data.bar.autoShowDelay + "ms"
    }
  }
}
